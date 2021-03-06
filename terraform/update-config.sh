#!/bin/bash

set -eu

# Get k8s version.
export k8s_version=$(kubectl version --short | grep -i "Server" | sed -E 's/^Server Version: (v[0-9]+\.[0-9]+\.[0-9]+).*$/\1/g')

# Export userdata template substitution variables.
export node_nametag="${node_nametag}"
export aws_access_key_id="${aws_access_key_id}"
export aws_secret_access_key="${aws_secret_access_key}"
export aws_region="${aws_region}"
export default_instance_type="${default_instance_type}"
export default_volume_size="${default_volume_size}"
export boot_image_tags="${boot_image_tags}"
export license_key="${license_key}"
export license_id="${license_id}"
export license_username="${license_username}"
export license_password="${license_password}"
export itzo_url="${itzo_url}"
export itzo_version="${itzo_version}"
export milpa_image="${milpa_image}"
export pod_cidr="${pod_cidr:-255.255.255.255/32}"
export service_cidr="${service_cidr}"

# Set server-url for kiyot.
export server_url="$(kubectl config view -ojsonpath='{.clusters[0].cluster.server}')"

# Enable masquerade-all in kube-proxy. Only needed if kiyot-kube-proxy is in
# use, see below.
# kubectl -n kube-system get cm kube-proxy-config -oyaml | sed 's/\(^\s*masqueradeAll:\).*$/\1 true/' | kubectl replace -f -

# Deploy kiyot components.
curl -fL https://raw.githubusercontent.com/elotl/milpa-deploy/master/deploy/kiyot.yaml | envsubst | kubectl apply -f -

# Uncomment this if the fargate backend is in use. In that case, we also need
# to start a kube-proxy pod for cells, since fargate cells don't have their own
# service proxy running.
# curl -fL https://raw.githubusercontent.com/elotl/milpa-deploy/master/deploy/kiyot-kube-proxy-eks.yaml | envsubst | kubectl apply -f -

curl -fL https://raw.githubusercontent.com/elotl/milpa-deploy/master/deploy/kiyot-device-plugin.yaml | envsubst | kubectl apply -f -

curl -fL https://raw.githubusercontent.com/elotl/milpa-deploy/master/deploy/create-webhook.sh | bash -s -- --no-wait-for-control-plane
