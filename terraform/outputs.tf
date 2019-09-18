#
# Outputs
#

data "aws_instances" "eks-workers" {
  depends_on = [
    "aws_autoscaling_group.milpa-workers",
    "aws_autoscaling_group.workers"
  ]
  instance_tags = {
    Name = "terraform-milpa-eks-${var.cluster-name}"
  }
}

output "worker-ips" {
  value = "${data.aws_instances.eks-workers.public_ips}"
}
