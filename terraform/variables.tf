#
# Variables Configuration
#

variable "cluster-name" {
  type    = "string"
}

variable "ssh-key-name" {
  type    = "string"
}

variable "aws-access-key-id" {
  type = "string"
}

variable "aws-secret-access-key" {
  type = "string"
}

variable "default-instance-type" {
  type = "string"
  default = "t3.large"
}

variable "default-volume-size" {
  type = "string"
  default = "15Gi"
}

variable "license-key" {
  type = "string"
}

variable "license-id" {
  type = "string"
}

variable "license-username" {
  type = "string"
}

variable "license-password" {
  type = "string"
}
