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
  name        = "terraform-eks-worker-node"
  description = "Security group for all nodes in the cluster"
  vpc_id      = "${aws_vpc.demo.id}"

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
    cidr_blocks = ["${aws_vpc.demo.cidr_block}"]
  }

  tags = "${
    map(
     "Name", "terraform-eks-worker-node",
     "kubernetes.io/cluster/${var.cluster-name}", "owned",
    )
  }"
}

resource "aws_security_group_rule" "worker-node-ingress-self" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = "${aws_security_group.worker-node.id}"
  source_security_group_id = "${aws_security_group.worker-node.id}"
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "worker-node-ingress-cluster" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.worker-node.id}"
  source_security_group_id = "${aws_security_group.demo-cluster.id}"
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "worker-node-ingress-ssh" {
  description              = "Allow SSH access to worker nodes"
  from_port                = 0
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.worker-node.id}"
  cidr_blocks              = ["0.0.0.0/0"]
  to_port                  = 22
  type                     = "ingress"
}

data "aws_ami" "eks-worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${aws_eks_cluster.demo.version}-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}

# Userdata for regular workers and Milpa workers.
locals {
  worker-userdata = <<USERDATA
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.demo.endpoint}' --b64-cluster-ca '${aws_eks_cluster.demo.certificate_authority.0.data}' '${var.cluster-name}'
USERDATA

  milpa-worker-userdata = <<USERDATA
#!/bin/bash
set -o xtrace
yum -y install jq python-pip
mkdir -p /etc/cni/net.d
mkdir -p /etc/kubernetes/pki && echo "${aws_eks_cluster.demo.certificate_authority.0.data}" > /etc/kubernetes/pki/ca.crt
curl -L -O https://download.elotl.co/milpa-installer-latest && chmod 755 milpa-installer-latest
./milpa-installer-latest
pip install yq
yq -y ".clusterName=\"${var.cluster-name}\" | .cloud.aws.accessKeyID=\"${var.aws-access-key-id}\" | .cloud.aws.secretAccessKey=\"${var.aws-secret-access-key}\" | .cloud.aws.vpcID=\"\" | .nodes.defaultInstanceType=\"${var.default-instance-type}\" | .nodes.defaultVolumeSize=\"${var.default-volume-size}\" | .license.key=\"${var.license-key}\" | .license.id=\"${var.license-id}\" | .license.username=\"${var.license-username}\" | .license.password=\"${var.license-password}\"" /opt/milpa/etc/server.yml > /opt/milpa/etc/server.yml.new && mv /opt/milpa/etc/server.yml.new /opt/milpa/etc/server.yml
sed -i 's#--milpa-endpoint 127.0.0.1:54555$#--milpa-endpoint 127.0.0.1:54555 --service-cluster-ip-range 172.20.0.0/16#' /etc/systemd/system/kiyot.service
sed -i 's#--config /opt/milpa/etc/server.yml$#--config /opt/milpa/etc/server.yml --delete-cluster-lock-file#' /etc/systemd/system/milpa.service
mkdir -p /etc/systemd/system/kubelet.service.d/
echo -e "[Service]\nStartLimitInterval=0\nStartLimitIntervalSec=0\nRestart=always\nRestartSec=5" > /etc/systemd/system/kubelet.service.d/override.conf
systemctl daemon-reload
systemctl restart milpa; systemctl restart kiyot
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.demo.endpoint}' --b64-cluster-ca '${aws_eks_cluster.demo.certificate_authority.0.data}' --kubelet-extra-args '--container-runtime=remote --container-runtime-endpoint=/opt/milpa/run/kiyot.sock --max-pods=1000' '${var.cluster-name}'
sed -i '/docker/d' /etc/systemd/system/kubelet.service
systemctl daemon-reload
systemctl stop docker
rm -f /var/run/docker.sock; touch /var/run/docker.sock
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
  vpc_zone_identifier  = "${aws_subnet.demo.*.id}"

  tag {
    key                 = "Name"
    value               = "terraform-milpa-eks-${var.cluster-name}"
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
  vpc_zone_identifier  = "${aws_subnet.demo.*.id}"

  tag {
    key                 = "Name"
    value               = "terraform-milpa-eks-${var.cluster-name}"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster-name}"
    value               = "owned"
    propagate_at_launch = true
  }
}
