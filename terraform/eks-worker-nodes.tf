#
# EKS Worker Nodes Resources
#  * IAM role allowing Kubernetes actions to access other AWS services
#  * EC2 Security Group to allow networking traffic
#  * Data source to fetch latest EKS worker AMI
#  * AutoScaling Launch Configuration to configure worker instances
#  * AutoScaling Group to launch worker instances
#

resource "aws_iam_role" "worker-node" {
  name_prefix = "${var.cluster-name}-node-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

locals {
  config_map_aws_auth = <<CONFIGMAPAWSAUTH
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${aws_iam_role.worker-node.arn}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
CONFIGMAPAWSAUTH
}

resource "null_resource" "allow-join" {
  depends_on = [
    "aws_iam_role.worker-node",
    "null_resource.update-config"
  ]

  provisioner "local-exec" {
    command = "echo '${local.config_map_aws_auth}' | kubectl apply -f -"
    environment = {
      KUBECONFIG = "kubeconfig"
    }
  }
}

resource "aws_iam_role_policy_attachment" "worker-node-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = "${aws_iam_role.worker-node.name}"
}

resource "aws_iam_role_policy_attachment" "worker-node-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = "${aws_iam_role.worker-node.name}"
}

resource "aws_iam_role_policy_attachment" "worker-node-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = "${aws_iam_role.worker-node.name}"
}

resource "aws_iam_role_policy" "k8s-milpa" {
  name = "k8s-milpa-${var.cluster-name}"
  role = "${aws_iam_role.worker-node.name}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ec2",
      "Effect": "Allow",
      "Action": [
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CreateRoute",
        "ec2:CreateSecurityGroup",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:DeleteRoute",
        "ec2:DeleteSecurityGroup",
        "ec2:DescribeAddresses",
        "ec2:DescribeElasticGpus",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeRouteTables",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSpotPriceHistory",
        "ec2:DescribeSubnets",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DescribeVpcAttribute",
        "ec2:DescribeVpcs",
        "ec2:ModifyInstanceAttribute",
        "ec2:ModifyInstanceCreditSpecification",
        "ec2:ModifyVolume",
        "ec2:ModifyVpcAttribute",
        "ec2:RequestSpotInstances",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ecr:BatchGetImage",
        "ecr:GetAuthorizationToken",
        "ecr:GetDownloadUrlForLayer"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "worker-node" {
  name = "${var.cluster-name}-eks-profile"
  role = "${aws_iam_role.worker-node.name}"
}

resource "aws_security_group" "worker-node" {
  name        = "eks-worker-node-${var.cluster-name}"
  description = "Security group for all nodes in the cluster"
  vpc_id      = "${aws_vpc.vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${aws_vpc.vpc.cidr_block}"]
  }

  ingress {
    from_port                = 1025
    to_port                  = 65535
    protocol                 = "tcp"
    security_groups = ["${aws_security_group.clustersg.id}"]
  }

  ingress {
    from_port                = 22
    to_port                  = 22
    protocol                 = "tcp"
    cidr_blocks              = ["0.0.0.0/0"]
  }

  tags = "${
    map(
     "Name", "eks-worker-node-${var.cluster-name}",
     "kubernetes.io/cluster/${var.cluster-name}", "owned",
    )
  }"
}

data "aws_ami" "eks-worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${aws_eks_cluster.cluster.version}-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}

# Userdata for regular workers and Milpa workers.
locals {
  worker-userdata = <<USERDATA
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.cluster.endpoint}' --b64-cluster-ca '${aws_eks_cluster.cluster.certificate_authority.0.data}' '${var.cluster-name}'
USERDATA

  milpa-worker-userdata = <<USERDATA
#!/bin/bash
set -o xtrace
# Configure system.
cat > /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
# Setup required sysctl params, these persist across reboots.
cat > /etc/sysctl.d/99-kubernetes-cri.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system
# Remove docker.
yum -y remove docker
# Install runc and containerd.
curl -fL https://github.com/opencontainers/runc/releases/download/v1.0.0-rc8/runc.amd64 > /tmp/runc
install -m 0755 /tmp/runc /usr/local/bin/
curl -fL https://github.com/containerd/containerd/releases/download/v1.2.7/containerd-1.2.7.linux-amd64.tar.gz > /tmp/containerd.tgz
tar -C /usr/local -xvf /tmp/containerd.tgz
mkdir -p /etc/containerd
/usr/local/bin/containerd config default > /etc/containerd/config.toml
cat <<EOF > /etc/systemd/system/containerd.service
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target
[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/containerd
Delegate=yes
KillMode=process
Restart=always
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=1048576
# Comment TasksMax if your systemd version does not supports it.
# Only systemd 226 and above support this version.
TasksMax=infinity
[Install]
WantedBy=multi-user.target
EOF
# Install criproxy.
curl -fL https://github.com/elotl/criproxy/releases/download/v0.15.0/criproxy > /usr/local/bin/criproxy; chmod 755 /usr/local/bin/criproxy
cat <<EOF > /etc/systemd/system/criproxy.service
[Unit]
Description=CRI Proxy
Wants=containerd.service
[Service]
ExecStart=/usr/local/bin/criproxy -v 3 -logtostderr -connect /run/containerd/containerd.sock,kiyot:/run/milpa/kiyot.sock -listen /run/criproxy.sock
Restart=always
StartLimitInterval=0
RestartSec=10
[Install]
WantedBy=kubelet.service
EOF
systemctl daemon-reload
systemctl restart criproxy
# Configure kubelet.
mkdir -p /etc/kubernetes/pki && echo "${aws_eks_cluster.cluster.certificate_authority.0.data}" > /etc/kubernetes/pki/ca.crt
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.cluster.endpoint}' --b64-cluster-ca '${aws_eks_cluster.cluster.certificate_authority.0.data}' --kubelet-extra-args '--container-runtime=remote --container-runtime-endpoint=/run/criproxy.sock --max-pods=1000 --node-labels=kubernetes.io/role=milpa-worker' --use-max-pods false '${var.cluster-name}'
sed -i '/docker/d' /etc/systemd/system/kubelet.service
# Override number of CPUs and memory cadvisor reports.
infodir=/opt/kiyot/proc
mkdir -p $infodir; rm -f $infodir/{cpu,mem}info
for i in $(seq 0 1023); do
    cat << EOF >> $infodir/cpuinfo
processor	: $i
physical id	: 0
core id		: 0
cpu MHz		: 2400.068
EOF
done
mem=$((4096*1024*1024))
cat << EOF > $infodir/meminfo
$(printf "MemTotal:%15d kB" $mem)
SwapTotal:             0 kB
EOF
cat <<EOF > /etc/systemd/system/kiyot-override-proc.service
[Unit]
Description=Override /proc info files
Before=kubelet.service
[Service]
Type=oneshot
ExecStart=/bin/mount --bind $infodir/cpuinfo /proc/cpuinfo
ExecStart=/bin/mount --bind $infodir/meminfo /proc/meminfo
RemainAfterExit=true
ExecStop=/bin/umount /proc/cpuinfo
ExecStop=/bin/umount /proc/meminfo
StandardOutput=journal
EOF
systemctl daemon-reload
systemctl start kiyot-override-proc
systemctl restart kubelet
USERDATA
}

# We create two launch configs and two AS groups, one for Milpa workers, the
# second one for regular worker nodes.
resource "aws_launch_configuration" "milpa-worker" {
  associate_public_ip_address = true
  iam_instance_profile        = "${aws_iam_instance_profile.worker-node.name}"
  image_id                    = "${data.aws_ami.eks-worker.id}"
  instance_type               = "t3.small"
  name_prefix                 = "${var.cluster-name}-eks-milpa-launch-configuration"
  security_groups             = ["${aws_security_group.worker-node.id}"]
  user_data_base64            = "${base64encode(local.milpa-worker-userdata)}"
  key_name = "${var.ssh-key-name}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_configuration" "worker" {
  associate_public_ip_address = true
  iam_instance_profile        = "${aws_iam_instance_profile.worker-node.name}"
  image_id                    = "${data.aws_ami.eks-worker.id}"
  instance_type               = "m5.large"
  name_prefix                 = "${var.cluster-name}-eks-launch-configuration"
  security_groups             = ["${aws_security_group.worker-node.id}"]
  user_data_base64            = "${base64encode(local.worker-userdata)}"
  key_name = "${var.ssh-key-name}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "milpa-workers" {
  desired_capacity     = 1
  launch_configuration = "${aws_launch_configuration.milpa-worker.id}"
  max_size             = 1
  min_size             = 1
  name                 = "${var.cluster-name}-milpa-workers"
  vpc_zone_identifier  = "${aws_subnet.subnets.*.id}"

  tag {
    key                 = "Name"
    value               = "eks-${var.cluster-name}-milpa-worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster-name}"
    value               = "owned"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group" "workers" {
  desired_capacity     = 1
  launch_configuration = "${aws_launch_configuration.worker.id}"
  max_size             = 1
  min_size             = 1
  name                 = "${var.cluster-name}-workers"
  vpc_zone_identifier  = "${aws_subnet.subnets.*.id}"

  tag {
    key                 = "Name"
    value               = "eks-${var.cluster-name}-worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster-name}"
    value               = "owned"
    propagate_at_launch = true
  }
}
