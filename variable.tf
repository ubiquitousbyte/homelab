variable "hcloud_token" {
  sensitive   = true
  type        = string
  description = "Personal access token for interacting with HCloud."
}

variable "hcloud_public_key" {
  type        = string
  description = "Public key to be installed on all HCloud machines."
}

variable "home_ip" {
  sensitive   = true
  type        = string
  description = "IP address @ home."
}
