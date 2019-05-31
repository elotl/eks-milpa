# Create a Nodeless Kubernetes Cluster on EKS with Milpa

## Introduction

This document will go through the steps required to get a nodeless kubernetes cluster up and running on Amazon EKS with [Milpa](https://www.elotl.co/milpadocs) and [Kiyot](https://www.elotl.co/kiyotdocs).

Prerequisites:
* An AWS account that can create and manage EKS clusters.
* A license for Milpa. Get one for free [here](https://www.elotl.co/trial).
* Terraform is used for provisioning the EKS cluster. Get it [here](https://www.terraform.io/downloads.html).
* Kubectl for interacting with Kubernetes. Install a compatible version from [here](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl). Kubectl supports one release of version skew, and here we use Kubernetes 1.10, so you will need kubectl 1.10 or 1.11.

Note: creating and running an EKS cluster on AWS will cost you money.

## Create an EKS Cluster

You will find a Terraform configuration in `terraform/`. Feel free to poke around, check out the .tf files, etc.

Next, you need to set a few variables for your new EKS cluster.

```
$ cd terraform/
$ vi env.tfvars # Check the comments in the file to see what each variables does.
```

Once you set all the variables, you are ready to create the cluster:

```
$ terraform init # Only needed the first time you run terraform in this directory.

Initializing provider plugins...
- Checking for available provider plugins on https://releases.hashicorp.com...
- Downloading plugin for provider "aws" (2.2.0)...

[...]

Plan: 26 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value:
```

Type `yes`, and terraform will start creating your EKS infrastructure. This will take a few minutes to complete. When it finishes, you will see some output from terraform like this:

```
Outputs:

config_map_aws_auth =

apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: arn:aws:iam::689494258501:role/terraform-eks-demo-node
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes

kubeconfig =

apiVersion: v1
clusters:
- cluster:
    server: https://151728AA66F2D872AB6D4612FCFB10BE.yl4.us-east-1.eks.amazonaws.com
    certificate-authority-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUN5RENDQWJDZ0F3SUJBZ0lCQURBTkJna3Foa2lHOXcwQkFRc0ZBREFWTVJNd0VRWURWUVFERXdwcmRXSmwKY201bGRHVnpNQjRYRFRFNU1ETXhOVEl4TlRFeE1Gb1hEVEk1TURNeE1qSXhOVEV4TUZvd0ZURVRNQkVHQTFVRQpBeE1LYTNWaVpYSnVaWFJsY3pDQ0FTSXdEUVlKS29aSWh2Y05BUUVCQlFBRGdnRVBBRENDQVFvQ2dnRUJBS2R5ClNPbm4ra0FnREd1cU81RjhyRFpXMWJqcHFManRlMjNNK3NXays5TjhsVDY3M3BmWkdxWkE4VURaUU5UT2pOWjQKQ09Mdm1GL3ZDamZwWnIyenpseU90K2E0MzZVdlBhcEtSOTFLLzhPY3BzYUluWTNMVTBVNmhQWTdNNENXcFdWSwpvS3Mvby8wQ3dhS0FUN3lTUWVGK0FwTjhybE9NcWJzV1RpbnFtV1R3NEFKOUpaY2ZhWElyaE9kMk1qTzBCcXJjCndVTXBUbU9DMHRqY013a1VHaWl2VkZkNUtKSUVhaW9xa05OT0ZYbHlIVS8xQitQUXY3Y1hpV0Z1YW9nSUZ4Q0cKZzBPaEFjSmdjaTJKODdmQUJhMENqYXlobzdyUUtBWkg1V1p4Z2ZSc0tBTEo3MitTOWtSbjJQSlpkZWtjSTZPdApzNTdsNFVidlBKbm1vbEUwbXlVQ0F3RUFBYU1qTUNFd0RnWURWUjBQQVFIL0JBUURBZ0trTUE4R0ExVWRFd0VCCi93UUZNQU1CQWY4d0RRWUpLb1pJaHZjTkFRRUxCUUFEZ2dFQkFKNkJCSGJYb1pjT3RNK3ZvWVRaWFJRSkNOZUMKV05xZjJNbHBvVEtFdi9ScjdJK1lxaWM0dlpucnZyQTNSZ21wdk1xV0M1V3MrOEZobGU3RHk5cFR3RE8zVWtlcQovS3p4ZTR1Ujl1QXpQc0tUaEhSTVVsdEd0a3FtSG5zYW5yRnFRSklEQnF3OG83YVZsZk15SkhndHRkenozSEF0Ck5oRjNTZUZpVzVlVmhDa0RzV3NQejFQbXZ0UkdUcEd4YzVBWnFHWHYzYjFNUjloWXd6aUE4anBSbGJaanVXRjcKWTR0eDNEaXVFTk5PYVplVGEvYmhaYy90Y2JnKzhNc2FUWTh4WGpUbklTaWp6MDJScHk2bDlmNWgyeC9aQU1wcwppTTNVVTJwTnBzUkpsTzV0anovT2NubGFYUE1ibEJJS3I5a3BDd0loNjg5VWdKcXRHSmRiSjI0OUNsZz0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo=
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: aws
  name: aws
current-context: aws
kind: Config
preferences: {}
users:
- name: aws
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: aws-iam-authenticator
      args:
        - "token"
        - "-i"
        - "vilmos-eks-test"

worker-ips = [
    3.94.163.95
]
```

## Configure your Cluster

Save the items from the `terraform apply` run output:
* `config_map_aws_auth` as `config_map_aws_auth.yaml`.
* `kubeconfig` as `~/.kube/config`. You might already have existing Kubernetes clusters configured in this configuration file, in which case you should add it to the existing list.

Now allow Kiyot to connect to the API server as the anonymous user:

```
$ kubectl create clusterrolebinding cluster-system-anonymous --clusterrole=cluster-admin --user=system:anonymous
```

Allow your worker to join the cluster:

```
$ kubectl apply -f config_map_aws_auth.yaml
```

Now the API server allows connections from the kubelet and kiyot. If you  ssh into the worker node, you can check out that all required services (milpa, kiyot and kubelet) are up and running (the IP address is in the output of `terraform apply`, check `worker-ips`).

Next, delete the `aws-node` daemonset. This starts a CNI plugin on workers, which is unnecessary with Milpa and Kiyot.

```
$ kubectl -n kube-system get ds
NAME         DESIRED   CURRENT   READY     UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
aws-node     0         0         0         0            0           <none>          1m
kube-proxy   0         0         0         0            0           <none>          1m
$ kubectl -n kube-system delete daemonset aws-node
daemonset.extensions "aws-node" deleted
```

Update the configuration for kube-proxy:

```
$ kubectl -n kube-system edit daemonset -oyaml kube-proxy
```

Update `command` for the kube-proxy container in `/tmp/kube-proxy-ds.yaml` to include `--masquerade-all`. It should look something like this (make sure that you only add `--masquerade-all`, and leave the other configuration options in place):

```
[...]
      containers:
      - command:
        - /bin/sh
        - -c
        - kube-proxy --masquerade-all --resource-container="" --oom-score-adj=-998 --master=...
        image: 602401143452.dkr.ecr.us-east-1.amazonaws.com/eks/kube-proxy:v1.10.3
        imagePullPolicy: IfNotPresent
        name: kube-proxy
[...]
daemonset.extensions/kube-proxy edited
```

Once kube-proxy gets updated, the system pods should come up:

```
$ kubectl get pods --all-namespaces
NAMESPACE     NAME                        READY     STATUS    RESTARTS   AGE
kube-system   kube-dns-6f455bb957-t42mt   3/3       Running   0          27m
kube-system   kube-proxy-db4rx            1/1       Running   0          4m
```

At this point your cluster is ready for deploying your applications. You can go through our [Kiyot tutorials](https://static.elotl.co/docs/latest/kiyot/kiyot.html#tutorials) to get started.

## Cleanup

To remove all resources:

```
$ kubectl delete --all pods --namespace=default
pod "frontend-5c548f4769-dnr5m" deleted
pod "frontend-5c548f4769-hrpnj" deleted
pod "frontend-5c548f4769-rfzr4" deleted
pod "redis-master-55db5f7567-fbgsm" deleted
pod "redis-slave-584c66c5b5-d4nzh" deleted
pod "redis-slave-584c66c5b5-fnwhg" deleted
$ kubectl delete --all deployments --namespace=default
deployment.extensions "frontend" deleted
deployment.extensions "redis-master" deleted
deployment.extensions "redis-slave" deleted
$ kubectl delete --all services --namespace=default
service "frontend" deleted
service "kubernetes" deleted
$ kubectl delete --all pods --namespace=kube-system
pod "kube-dns-6f455bb957-t42mt" deleted
pod "kube-proxy-db4rx" deleted
pod "kubernetes-dashboard-669f9bbd46-g4zhm" deleted
$ kubectl delete --all deployments --namespace=kube-system
deployment.extensions "kube-dns" deleted
deployment.extensions "kubernetes-dashboard" deleted
$ kubectl delete --all services --namespace=kube-system
service "kube-dns" deleted
service "kubernetes-dashboard" deleted
$ kubectl delete --all daemonsets --namespace=kube-system
daemonset.extensions "kube-proxy" deleted
```

Now you can remove all resources via terraform:

```
$ terraform destroy -var-file env.tfvars
```
