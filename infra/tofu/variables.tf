# Input variables for the VM layer.
#
# Every variable that could damage a node if it were wrong has no default. The
# layer fails closed: `tofu plan` stops and names the missing value, instead of
# guessing one.

variable "proxmox_insecure_tls" {
  description = <<-EOT
    Skip Proxmox API TLS verification. The PVE nodes serve a self-signed
    certificate, so this is `true` today. Set it back to `false` after the
    cluster gets a trusted certificate.
  EOT
  type        = bool
  default     = false
}
