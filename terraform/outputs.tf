#
# Outputs
#

data "aws_instances" "eks-workers" {
  depends_on = [ "aws_autoscaling_group.demo" ]
  instance_tags {
    Name = "terraform-eks-demo"
  }
}

output "worker-ips" {
  value = "${data.aws_instances.eks-workers.public_ips}"
}
