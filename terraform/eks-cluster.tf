#
# EKS Cluster Resources
#  * IAM Role to allow EKS service to manage other AWS services
#  * EC2 Security Group to allow networking traffic with EKS cluster
#  * EKS Cluster
#

resource "aws_iam_role" "demo-cluster" {
  name_prefix = "${var.cluster-name}-cluster-role"

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
  role = "${aws_iam_role.demo-cluster.id}"

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

resource "aws_iam_role_policy_attachment" "demo-cluster-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = "${aws_iam_role.demo-cluster.name}"
}

resource "aws_iam_role_policy_attachment" "demo-cluster-AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = "${aws_iam_role.demo-cluster.name}"
}

resource "aws_security_group" "demo-cluster" {
  name        = "terraform-eks-demo-cluster"
  description = "Cluster communication with worker nodes"
  vpc_id      = "${aws_vpc.demo.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform-eks-demo"
  }
}

resource "aws_security_group_rule" "demo-cluster-ingress-workstation-https" {
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow access to the cluster API Server"
  from_port         = 443
  protocol          = "tcp"
  security_group_id = "${aws_security_group.demo-cluster.id}"
  to_port           = 443
  type              = "ingress"
}

resource "aws_eks_cluster" "demo" {
  name     = "${var.cluster-name}"
  role_arn = "${aws_iam_role.demo-cluster.arn}"
  version  = "1.14"

  vpc_config {
    security_group_ids = ["${aws_security_group.demo-cluster.id}"]
    subnet_ids         = "${aws_subnet.demo.*.id}"
  }

  depends_on = [
    "aws_iam_role_policy_attachment.demo-cluster-AmazonEKSClusterPolicy",
    "aws_iam_role_policy_attachment.demo-cluster-AmazonEKSServicePolicy",
  ]
}

locals {
  kubeconfig = <<KUBECONFIG
apiVersion: v1
clusters:
- cluster:
    server: ${aws_eks_cluster.demo.endpoint}
    certificate-authority-data: ${aws_eks_cluster.demo.certificate_authority.0.data}
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
}

resource "null_resource" "update-config" {
  depends_on = ["aws_eks_cluster.demo"]

  provisioner "local-exec" {
    command = "echo \"${local.kubeconfig}\" > kubeconfig"
  }

  # Wait for the API endpoint to come up.
  provisioner "local-exec" {
    command = "timeout 300s sh -c 'while true; do kubectl get pods > /dev/null 2>&1 && break; sleep 1; done'"
    environment = {
      KUBECONFIG = "kubeconfig"
    }
  }

  # Allow view access to cluster resources for kiyot.
  provisioner "local-exec" {
    command = "bash update-config.sh"
    environment = {
      KUBECONFIG            = "kubeconfig"
      node_nametag          = var.cluster-name
      aws_access_key_id     = var.aws-access-key-id
      aws_secret_access_key = var.aws-secret-access-key
      aws_region            = var.region
      default_instance_type = var.default-instance-type
      default_volume_size   = var.default-volume-size
      boot_image_tags       = jsonencode(var.boot-image-tags)
      license_key           = var.license-key
      license_id            = var.license-id
      license_username      = var.license-username
      license_password      = var.license-password
      itzo_url              = var.itzo-url
      itzo_version          = var.itzo-version
      milpa_image           = var.milpa-image
    }
  }
}
