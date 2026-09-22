variable "hcloud_token" {
  sensitive   = true
  type        = string
  description = "Personal access token for interacting with HCloud."
}

variable "tailscale_authkey" {
  sensitive   = true
  type        = string
  description = "Tailscale auth key used to join machines to the tailnet at boot, via cloud-init."
}
