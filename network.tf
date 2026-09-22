provider "hcloud" {
  token = var.hcloud_token
}

data "http" "github_public_keys" {
  url = "https://github.com/ubiquitousbyte.keys"
}

locals {
  # One key per line; GitHub's .keys endpoint reflects whatever keys are
  # currently on the account, so adding/rotating a key needs no repo change.
  github_public_keys = compact(split("\n", data.http.github_public_keys.response_body))
}

resource "hcloud_ssh_key" "main" {
  for_each = toset(local.github_public_keys)

  name       = "github-${substr(md5(each.value), 0, 8)}"
  public_key = each.value
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

  # No public SSH: nodes join Tailscale at boot (see cx33.tf's cloud-init) and are
  # administered over Tailscale SSH / the tailnet from then on. Hetzner's own web
  # console is the break-glass path if Tailscale itself is ever unreachable.

  # Each role's .tf file (e.g. cx33.tf) contributes its servers here.
  dynamic "apply_to" {
    for_each = hcloud_server.cx33
    content {
      server = apply_to.value.id
    }
  }
}
