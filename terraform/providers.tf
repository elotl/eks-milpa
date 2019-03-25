#
# Provider Configuration
#

provider "aws" {
# You can also use environment variables instead of setting these variables:
# $ export AWS_ACCESS_KEY_ID="anaccesskey"
# $ export AWS_SECRET_ACCESS_KEY="asecretkey"
# $ export AWS_DEFAULT_REGION="us-east-1"
# See https://www.terraform.io/docs/providers/aws/ for more information.
#  region = "us-east-1"
#  access_key = ""
#  secret_key = ""
}

# Using these data sources allows the configuration to be
# generic for any region.
data "aws_region" "current" {}

data "aws_availability_zones" "available" {}
