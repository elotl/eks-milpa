#
# VPC Resources
#  * VPC
#  * Subnets
#  * Internet Gateway
#  * Route Table
#

resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"

  tags = "${
    map(
      "Name", "eks-${var.cluster-name}",
      "kubernetes.io/cluster/${var.cluster-name}", "shared",
    )
  }"

  provisioner "local-exec" {
    # Remove any leftover instance, security group etc Milpa created. They
    # would prevent terraform from destroying the VPC.
    when    = "destroy"
    command = "./cleanup-vpc.sh ${self.id}"
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "aws_subnet" "subnets" {
  count = 2

  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  cidr_block        = "10.0.${count.index}.0/24"
  vpc_id            = "${aws_vpc.vpc.id}"

  tags = "${
    map(
      "Name", "eks-${var.cluster-name}",
      "kubernetes.io/cluster/${var.cluster-name}", "shared",
    )
  }"
}

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags = {
    Name = "eks-${var.cluster-name}"
  }

  provisioner "local-exec" {
    # Remove any leftover instance, security group etc Milpa created. They
    # would prevent terraform from destroying the VPC.
    when    = "destroy"
    command = "./cleanup-vpc.sh ${self.vpc_id}"
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "aws_route_table" "rt" {
  vpc_id = "${aws_vpc.vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }
}

resource "aws_route_table_association" "rtassocs" {
  count = 2

  subnet_id      = "${aws_subnet.subnets.*.id[count.index]}"
  route_table_id = "${aws_route_table.rt.id}"
}
