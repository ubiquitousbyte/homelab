variable "cx33" {
  type = map(object({
    ip     = string
    labels = optional(map(string), {})
  }))
  description = "Map of cx33 machine name to its private IP on the cloud01 subnet (and optional labels)."
}

resource "hcloud_server" "cx33" {
  for_each = var.cx33

  name        = each.key
  server_type = "cx33"
  location    = "nbg1"
  image       = "ubuntu-24.04"
  ssh_keys    = [for k in hcloud_ssh_key.main : k.id]

  user_data = templatefile("${path.module}/cloud-init/tailscale.yaml.tftpl", {
    authkey = var.tailscale_authkey
  })

  labels = each.value.labels
}

resource "hcloud_server_network" "cx33" {
  for_each = var.cx33

  server_id = hcloud_server.cx33[each.key].id
  subnet_id = hcloud_network_subnet.cloud01.id
  ip        = each.value.ip
}
