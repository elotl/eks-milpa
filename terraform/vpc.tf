#
# VPC Resources
#  * VPC
#  * Subnets
#  * Internet Gateway
#  * Route Table
#

resource "aws_vpc" "vpc" {
  cidr_block = var.vpc-cidr
  enable_dns_hostnames = "true"

  provisioner "local-exec" {
    # Remove any leftover instance, security group etc Milpa created. They
    # would prevent terraform from destroying the VPC.
    when        = destroy
    command     = "./cleanup-vpc.sh ${self.id} ${var.cluster-name}"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      TF_AWS_REGION = "${data.aws_region.current.name}"
    }
  }
}

resource "aws_subnet" "subnets" {
  count = 2

  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block        = "10.0.${count.index}.0/24"
  vpc_id            = aws_vpc.vpc.id

  tags = merge(var.extra-tags, {
    "Name" = "eks-worker-node-${var.cluster-name}"
    "kubernetes.io/cluster/${var.cluster-name}" = "shared"
  })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  provisioner "local-exec" {
    # Remove any leftover instance, security group etc Milpa created. They
    # would prevent terraform from destroying the VPC.
    when        = destroy
    command     = "./cleanup-vpc.sh ${self.vpc_id} ${var.cluster-name}"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      TF_AWS_REGION = "${data.aws_region.current.name}"
    }
  }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  lifecycle {
    ignore_changes = [route]
  }
}

resource "aws_route_table_association" "rtassocs" {
  count = 2

  subnet_id      = aws_subnet.subnets[count.index].id
  route_table_id = aws_route_table.rt.id
}
