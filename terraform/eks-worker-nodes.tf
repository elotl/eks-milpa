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
    aws_iam_role.worker-node,
    null_resource.update-config,
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
  role       = aws_iam_role.worker-node.name
}

resource "aws_iam_role_policy_attachment" "worker-node-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.worker-node.name
}

resource "aws_iam_role_policy_attachment" "worker-node-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.worker-node.name
}

resource "aws_iam_role_policy" "k8s-milpa" {
  name   = "k8s-milpa-${var.cluster-name}"
  role   = aws_iam_role.worker-node.name
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
  role = aws_iam_role.worker-node.name
}

resource "aws_security_group" "worker-node" {
  name = "eks-worker-node-${var.cluster-name}"
  description = "Security group for all nodes in the cluster"
  vpc_id = aws_vpc.vpc.id

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }

  ingress {
    from_port = 1025
    to_port = 65535
    protocol = "tcp"
    security_groups = [aws_security_group.clustersg.id]
  }

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "Name" = "eks-worker-node-${var.cluster-name}"
    "kubernetes.io/cluster/${var.cluster-name}" = "owned"
  }
}

data "aws_ami" "eks-worker" {
  filter {
    name = "name"
    values = ["amazon-eks-node-${aws_eks_cluster.cluster.version}-v*"]
  }

  most_recent = true
  owners = ["602401143452"] # Amazon EKS AMI Account ID
}

data "aws_ami" "eks-milpa-worker" {
  filter {
    name = "name"
    values = ["eks-milpa-worker-${aws_eks_cluster.cluster.version}-v*"]
  }

  most_recent = true
  owners = ["689494258501"] # Elotl AWS Account ID
}

# Userdata for regular workers and Milpa workers.
locals {
  worker-userdata = <<USERDATA
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.cluster.endpoint}' --b64-cluster-ca '${aws_eks_cluster.cluster.certificate_authority[0].data}' '${var.cluster-name}'
USERDATA
}

# We create two launch configs and two AS groups, one for Milpa workers, the
# second one for regular worker nodes.
resource "aws_launch_configuration" "milpa-worker" {
  associate_public_ip_address = true
  iam_instance_profile = aws_iam_instance_profile.worker-node.name
  image_id = data.aws_ami.eks-milpa-worker.id
  instance_type = "t3.small"
  name_prefix = "${var.cluster-name}-eks-milpa-launch-configuration"
  security_groups = [aws_security_group.worker-node.id]
  user_data_base64 = base64encode(local.worker-userdata)
  key_name = var.ssh-key-name

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_configuration" "worker" {
  associate_public_ip_address = true
  iam_instance_profile = aws_iam_instance_profile.worker-node.name
  image_id = data.aws_ami.eks-worker.id
  instance_type = "m5.large"
  name_prefix = "${var.cluster-name}-eks-launch-configuration"
  security_groups = [aws_security_group.worker-node.id]
  user_data_base64 = base64encode(local.worker-userdata)
  key_name = var.ssh-key-name

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "milpa-workers" {
  desired_capacity = 1
  launch_configuration = aws_launch_configuration.milpa-worker.id
  max_size = 1
  min_size = 1
  name = "${var.cluster-name}-milpa-workers"
  vpc_zone_identifier = aws_subnet.subnets.*.id

  tag {
    key = "Name"
    value = "eks-${var.cluster-name}-milpa-worker"
    propagate_at_launch = true
  }

  tag {
    key = "kubernetes.io/cluster/${var.cluster-name}"
    value = "owned"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group" "workers" {
  desired_capacity = 1
  launch_configuration = aws_launch_configuration.worker.id
  max_size = 1
  min_size = 1
  name = "${var.cluster-name}-workers"
  vpc_zone_identifier = aws_subnet.subnets.*.id

  tag {
    key = "Name"
    value = "eks-${var.cluster-name}-worker"
    propagate_at_launch = true
  }

  tag {
    key = "kubernetes.io/cluster/${var.cluster-name}"
    value = "owned"
    propagate_at_launch = true
  }
}
