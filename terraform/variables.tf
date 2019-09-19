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

variable "region" {
  // Currently Milpa only supports us-east-1.
  default = "us-east-1"
}

variable "milpa-image" {
  default = "elotl/milpa"
}
