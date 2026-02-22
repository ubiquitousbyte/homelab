terraform {
  required_version = "~> 1.11"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

#                   Network: "main" (10.0.0.0/16)
# +---------------------------------------------------------------------------+
# |                                                                           |
# |              Subnet: "cloud01" (10.0.1.0/24, eu-central)                  |
# |  +---------------------------------------------------------------------+  |
# |  |                                                                     |  |
# |  |   +------------+   +------------+   +------------+   +------------+ |  |
# |  |   |   cx3301   |   |    cx3302  |   |  cx3303    |   |    cx3304  | |  |
# |  |   |            |   |            |   |            |   |            | |  |
# |  |   | 10.0.1.1   |   | 10.0.1.2   |   | 10.0.1.3   |   | 10.0.1.4   | |  |
# |  |   +-----+------+   +-----+------+   +-----+------+   +-----+------+ |  |
# |  |         |                |                |                |        |  |
# |  +---------|----------------|----------------|----------------|--------+  |
# |            |                |                |                |           |
# +---------------------------------------------------------------------------+
#                          |
#           +--------------+---------------+
#           | Firewall: "firewall01"       |
#           | TCP/22, internal             |
#           +--------------+---------------+
#                          |
#                          |  TCP/22 (SSH)
#                          |
#                          |
#                  +-------+--------+
#                  |    Home IP     |
#                  |  (home_ip/32)  |
#                  +----------------+

resource "hcloud_ssh_key" "main" {
  name       = "main"
  public_key = var.hcloud_public_key
}

resource "hcloud_network" "main" {
  name = "main"
  # This gives us (2^16)-2 available addresses, 
  # excluding the network address (10.0.0.0) and the broadcast address (10.0.255.255).
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "cloud01" {
  network_id   = hcloud_network.main.id
  type         = "cloud"
  network_zone = "eu-central"
  # 254 available addresses.
  ip_range = "10.0.1.0/24"
}

resource "hcloud_server" "cx3301" {
  name        = "cx3301"
  server_type = "cx33"
  location    = "nbg1"
  image       = "ubuntu-24.04"
  ssh_keys = [
    hcloud_ssh_key.main.id
  ]

  labels = {
    "role" : "nomad"
    "nomad_role" : "server"
  }
}

resource "hcloud_server_network" "cx3301_cloud01" {
  server_id = hcloud_server.cx3301.id
  subnet_id = hcloud_network_subnet.cloud01.id
  ip        = "10.0.1.1"
  alias_ips = []
}

resource "hcloud_server" "cx3302" {
  name        = "cx3302"
  server_type = "cx33"
  location    = "nbg1"
  image       = "ubuntu-24.04"
  ssh_keys = [
    hcloud_ssh_key.main.id
  ]

  labels = {
    "role" : "nomad"
    "nomad_role" : "client"
  }
}

resource "hcloud_server_network" "cx3302_cloud01" {
  server_id = hcloud_server.cx3302.id
  subnet_id = hcloud_network_subnet.cloud01.id
  ip        = "10.0.1.2"
  alias_ips = []
}

resource "hcloud_server" "cx3303" {
  name        = "cx3303"
  server_type = "cx33"
  location    = "nbg1"
  image       = "ubuntu-24.04"
  ssh_keys = [
    hcloud_ssh_key.main.id
  ]

  labels = {
    "role" : "nomad"
    "nomad_role" : "client"
  }
}

resource "hcloud_server_network" "cx3303_cloud01" {
  server_id = hcloud_server.cx3303.id
  subnet_id = hcloud_network_subnet.cloud01.id
  ip        = "10.0.1.3"
  alias_ips = []
}

resource "hcloud_server" "cx3304" {
  name        = "cx3304"
  server_type = "cx33"
  location    = "nbg1"
  image       = "ubuntu-24.04"
  ssh_keys = [
    hcloud_ssh_key.main.id
  ]

  labels = {
    "role" : "nomad"
    "nomad_role" : "client"
  }
}

resource "hcloud_server_network" "cx3304_cloud01" {
  server_id = hcloud_server.cx3304.id
  subnet_id = hcloud_network_subnet.cloud01.id
  ip        = "10.0.1.4"
  alias_ips = []
}


locals {
  ports = [
    "22",   # SSH
    "4646", # Nomad
  ]
}

resource "hcloud_firewall" "firewall01" {
  name = "firewall01"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "any"
    source_ips = ["10.0.1.0/24"]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "any"
    source_ips = ["10.0.1.0/24"]
  }

  dynamic "rule" {
    for_each = local.ports
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = rule.value
      source_ips = ["${var.home_ip}/32"]
    }
  }

  apply_to {
    server = hcloud_server.cx3301.id
  }
  apply_to {
    server = hcloud_server.cx3302.id
  }
  apply_to {
    server = hcloud_server.cx3303.id
  }
  apply_to {
    server = hcloud_server.cx3304.id
  }
}
