data "http" "client-ip" {
  url = "http://ipv4.icanhazip.com"
}

locals {
  client-cidr = "${chomp(data.http.client-ip.body)}/32"
}
