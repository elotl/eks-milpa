variable "ssh-key-name" {
}

variable "cluster-name" {
}

variable "aws-access-key-id" {
  // If empty, IAM will be used.
  default = ""
}

variable "aws-secret-access-key" {
  // If empty, IAM will be used.
  default = ""
}

variable "itzo-url" {
  // The URL to download the node agent from.
  default = "http://itzo-download.s3.amazonaws.com"
}

variable "itzo-version" {
  // The version of node agent to use.
  default = "latest"
}

variable "default-instance-type" {
  // This this the default cloud instance type. Pods that don't specify their
  // cpu and memory requirements will be launched on this instance type.
  // Example: "t3.nano".
  default = "t3.nano"
}

variable "default-volume-size" {
  // This this the default volume size used on the cloud instance. Example: "15Gi".
  default = "10Gi"
}

variable "boot-image-tags" {
  // This is a JSON dictionary of key-value pairs, describing the image tags
  // Milpa will use when finding the AMI to launch cloud instances with. Only
  // change it when you know what you are doing.
  default = {
    "company" = "elotl"
    "product" = "milpa"
  }
}

variable "license-key" {
  default = ""
}

variable "license-id" {
  default = ""
}

variable "license-username" {
  default = ""
}

variable "license-password" {
  default = ""
}

variable "milpa-image" {
  default = "elotl/milpa"
}

variable "blacklisted-azs" {
  // Blacklist certain AZs to prevent capacity problems. In us-east-1e, nitro
  // instances are not supported currently.
  type    = list(string)
  default = ["use1-az3"]
}

variable "milpa-worker-ami" {
  // This is the free worker AMI that has a limit of 50 Milpa pods.
  default = "ami-004afba2ba154f8e1"
  // To be able to use the paid AMI, you first need to subscribe to the
  // following AWS Marketplace offering:
  // https://aws.amazon.com/marketplace/pp/B082VDXGKQ
  // default = "ami-06040d7ede5c8f09a"
}

variable "milpa-worker-instance-type" {
  default = "c5.large"
}

variable "vpc-cidr" {
  default = "10.0.0.0/16"
}
