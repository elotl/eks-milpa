#!/bin/bash

set -eu

# Check what service IP CIDR is in use.
service_cidr="10.100.0.0/16"
ten_range=$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC/vpc-ipv4-cidr-blocks | grep -c '^10\..*' || true )
if [[ "$ten_range" != "0" ]] ; then
    service_cidr="172.20.0.0/16"
fi

# Enable masquerade-all in kube-proxy.
kubectl -n kube-system get cm kube-proxy-config -oyaml | sed 's/\(^\s*masqueradeAll:\).*$/\1 true/' | kubectl replace -f -

# Start a kube-proxy deployment for Milpa. This will route cluster IP traffic
# from Milpa pods.
cat <<EOF > /tmp/kube-proxy-milpa.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    k8s-app: kube-proxy
  name: kube-proxy
  namespace: kube-system
spec:
  selector:
    matchLabels:
      k8s-app: kube-proxy
  template:
    metadata:
      labels:
        k8s-app: kube-proxy
      annotations:
        kubernetes.io/target-runtime: kiyot
    spec:
      nodeSelector:
        kubernetes.io/role: milpa-worker
      containers:
      - image: 602401143452.dkr.ecr.us-east-1.amazonaws.com/eks/kube-proxy:v1.14.6
        command:
        - /bin/sh
        - -c
        - kube-proxy --v=2 --config=/var/lib/kube-proxy-config/config --hostname-override=\$(NODE_NAME)
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: spec.nodeName
        name: kube-proxy
        resources: {}
        securityContext:
          privileged: true
        volumeMounts:
        - mountPath: /var/log
          name: varlog
        - mountPath: /run/xtables.lock
          name: xtables-lock
        - mountPath: /lib/modules
          name: lib-modules
          readOnly: true
        - mountPath: /var/lib/kube-proxy/
          name: kubeconfig
        - mountPath: /var/lib/kube-proxy-config/
          name: config
      dnsPolicy: ClusterFirst
      hostNetwork: true
      priorityClassName: system-node-critical
      restartPolicy: Always
      securityContext: {}
      serviceAccount: kube-proxy
      serviceAccountName: kube-proxy
      terminationGracePeriodSeconds: 30
      volumes:
      - hostPath:
          path: /var/log
          type: ""
        name: varlog
      - hostPath:
          path: /run/xtables.lock
          type: FileOrCreate
        name: xtables-lock
      - hostPath:
          path: /lib/modules
          type: ""
        name: lib-modules
      - configMap:
          defaultMode: 420
          name: kube-proxy
        name: kubeconfig
      - configMap:
          defaultMode: 420
          name: kube-proxy-config
        name: config
EOF
kubectl apply -f /tmp/kube-proxy-milpa.yaml

cat <<EOF > /tmp/kiyot-device-plugin.yaml
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: kiyot-device-plugin
  namespace: kube-system
spec:
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        name: kiyot-device-plugin
    spec:
      priorityClassName: "system-node-critical"
      nodeSelector:
        kubernetes.io/role: milpa-worker
      containers:
      - image: elotl/kiyot-device-plugin:latest
        name: kiyot-device-plugin
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
        volumeMounts:
          - name: device-plugin
            mountPath: /var/lib/kubelet/device-plugins
      volumes:
        - name: device-plugin
          hostPath:
            path: /var/lib/kubelet/device-plugins
EOF
kubectl apply -f /tmp/kiyot-device-plugin.yaml

cat <<EOF > /tmp/kiyot-ds.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: milpa-config
  namespace: kube-system
data:
  SERVICE_CIDR: "${service_cidr}"
  server.yml: |
    apiVersion: v1
    cloud:
      aws:
        region: "${aws_region}"
        accessKeyID: "${aws_access_key_id}"
        secretAccessKey: "${aws_secret_access_key}"
        imageOwnerID: 689494258501
    etcd:
      internal:
        dataDir: /opt/milpa/data
    nodes:
      defaultInstanceType: "${default_instance_type}"
      defaultVolumeSize: "${default_volume_size}"
      bootImageTags: ${boot_image_tags}
      nametag: "${node_nametag}"
      itzo:
        url: "${itzo_url}"
        version: "${itzo_version}"
    license:
      key: "${license_key}"
      id: "${license_id}"
      username: "${license_username}"
      password: "${license_password}"
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kiyot
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kiyot-role
rules:
- apiGroups:
  - ""
  resources:
  - endpoints
  - services
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
- apiGroups:
  - apiextensions.k8s.io
  resources:
  - customresourcedefinitions
  verbs:
    - get
    - list
    - watch
    - create
    - delete
    - deletecollection
    - patch
    - update
- apiGroups:
  - kiyot.elotl.co
  resources:
  - cells
  verbs:
    - get
    - list
    - watch
    - create
    - delete
    - deletecollection
    - patch
    - update
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kiyot
roleRef:
  kind: ClusterRole
  name: kiyot-role
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: kiyot
  namespace: kube-system
---
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: kiyot
  namespace: kube-system
spec:
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        name: kiyot
    spec:
      priorityClassName: "system-node-critical"
      nodeSelector:
        kubernetes.io/role: milpa-worker
      restartPolicy: Always
      hostNetwork: true
      serviceAccountName: kiyot
      initContainers:
      - name: milpa-init
        image: "${milpa_image}"
        command:
        - bash
        - -c
        - "/milpa-init.sh /opt/milpa"
        volumeMounts:
        - name: optmilpa
          mountPath: /opt/milpa
        - name: server-yml
          mountPath: /etc/milpa
      containers:
      - name: kiyot
        image: "${milpa_image}"
        command:
        - /kiyot
        - --stderrthreshold=1
        - --logtostderr
        - --cert-dir=/opt/milpa/certs
        - --listen=/run/milpa/kiyot.sock
        - --milpa-endpoint=127.0.0.1:54555
        - --service-cluster-ip-range=\$(SERVICE_CIDR)
        - --kubeconfig=
        - --host-rootfs=/host-rootfs
        env:
        - name: SERVICE_CIDR
          valueFrom:
            configMapKeyRef:
              name: milpa-config
              key: SERVICE_CIDR
        securityContext:
          privileged: true
        volumeMounts:
        - name: optmilpa
          mountPath: /opt/milpa
        - name: run-milpa
          mountPath: /run/milpa
        - name: host-rootfs
          mountPath: /host-rootfs
          mountPropagation: HostToContainer
        - name: xtables-lock
          mountPath: /run/xtables.lock
        - name: lib-modules
          mountPath: /lib/modules
          readOnly: true
      - name: milpa
        image: "${milpa_image}"
        command:
        - /milpa
        - --stderrthreshold=1
        - --logtostderr
        - --cert-dir=/opt/milpa/certs
        - --config=/etc/milpa/server.yml
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: spec.nodeName
        volumeMounts:
        - name: optmilpa
          mountPath: /opt/milpa
        - name: server-yml
          mountPath: /etc/milpa
        - name: etc-machineid
          mountPath: /etc/machine-id
          readOnly: true
      volumes:
      - name: optmilpa
        hostPath:
          path: /opt/milpa
          type: DirectoryOrCreate
      - name: server-yml
        configMap:
          name: milpa-config
          items:
          - key: server.yml
            path: server.yml
            mode: 0600
      - name: etc-machineid
        hostPath:
          path: /etc/machine-id
      - name: run-milpa
        hostPath:
          path: /run/milpa
      - name: host-rootfs
        hostPath:
          path: /
      - name: xtables-lock
        hostPath:
          path: /run/xtables.lock
          type: FileOrCreate
      - name: lib-modules
        hostPath:
          path: /lib/modules
EOF
kubectl apply -f /tmp/kiyot-ds.yaml
