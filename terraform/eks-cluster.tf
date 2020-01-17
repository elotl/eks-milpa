#
# EKS Cluster Resources
#  * IAM Role to allow EKS service to manage other AWS services
#  * EC2 Security Group to allow networking traffic with EKS cluster
#  * EKS Cluster
#

resource "aws_iam_role" "eks-role" {
  name_prefix = "${var.cluster-name}-eks-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy" "eks-policy" {
  name_prefix = "${var.cluster-name}-eks-policy"
  role = aws_iam_role.eks-role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "eks:*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "cluster-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks-role.name
}

resource "aws_iam_role_policy_attachment" "cluster-AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks-role.name
}

resource "aws_security_group" "clustersg" {
  name        = "eks-${var.cluster-name}"
  description = "Cluster communication with worker nodes"
  vpc_id      = aws_vpc.vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port         = 443
    to_port           = 443
    protocol          = "tcp"
    cidr_blocks       = [local.client-cidr, aws_vpc.vpc.cidr_block]
    description       = "Allow access to the cluster API Server"
  }

  tags = merge(var.extra-tags, {
    Name = "eks-${var.cluster-name}"
  })
}

resource "null_resource" "check-dependencies" {
  provisioner "local-exec" {
    command = <<EOS
      for d in aws aws-iam-authenticator kubectl; do
          echo Checking if $d is available
          which $d > /dev/null 2>&1
      done
EOS
  }
}

resource "aws_eks_cluster" "cluster" {
  name     = var.cluster-name
  role_arn = aws_iam_role.eks-role.arn
  version  = "1.14"

  vpc_config {
    security_group_ids = [aws_security_group.clustersg.id]
    subnet_ids         = aws_subnet.subnets.*.id
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster-AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster-AmazonEKSServicePolicy,
    null_resource.check-dependencies,
  ]
}

locals {
  kubeconfig = <<KUBECONFIG
apiVersion: v1
clusters:
- cluster:
    server: ${aws_eks_cluster.cluster.endpoint}
    certificate-authority-data: ${aws_eks_cluster.cluster.certificate_authority[0].data}
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
        - "${var.cluster-name}"
KUBECONFIG
service-cidr = substr(aws_vpc.vpc.cidr_block, 0, 3) != "10." ? "10.100.0.0/16" : "172.20.0.0/16"
}

resource "null_resource" "update-config" {
  depends_on = [aws_eks_cluster.cluster]

  triggers = {
    update_config_file = "${sha1(file("${path.module}/update-config.sh"))}"
 }

  provisioner "local-exec" {
    command = "echo \"${local.kubeconfig}\" > kubeconfig"
  }

  # Wait for the API endpoint to come up.
  provisioner "local-exec" {
    command = "sh -c 'i=0; while [ $i -lt 300 ]; do kubectl get pods > /dev/null 2>&1 && exit 0; i=$((i+1)); sleep 1; done; exit 1'"
    environment = {
      KUBECONFIG = "kubeconfig"
    }
  }

  provisioner "local-exec" {
    command = "bash update-config.sh"
    environment = {
      KUBECONFIG = "kubeconfig"
      vpc_cidr = aws_vpc.vpc.cidr_block
      service_cidr = local.service-cidr
      node_nametag = var.cluster-name
      aws_access_key_id = var.aws-access-key-id
      aws_secret_access_key = var.aws-secret-access-key
      aws_region = data.aws_region.current.name
      default_instance_type = var.default-instance-type
      default_volume_size = var.default-volume-size
      boot_image_tags = jsonencode(var.boot-image-tags)
      license_key = var.license-key
      license_id = var.license-id
      license_username = var.license-username
      license_password = var.license-password
      itzo_url = var.itzo-url
      itzo_version = var.itzo-version
      milpa_image = var.milpa-image
    }
  }
}
