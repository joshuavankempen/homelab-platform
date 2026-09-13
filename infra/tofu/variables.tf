# Input variables for the VM layer.
#
# Every variable that could damage a node if it were wrong has no default. The
# layer fails closed: `tofu plan` stops and names the missing value, instead of
# guessing one.
#
# Sizes and placement carry defaults, because the 2026-09-14 discovery measured
# the real numbers and ADR-0005 records the decision. A default here is a
# recorded choice, not a guess.

variable "proxmox_insecure_tls" {
  description = <<-EOT
    Skip Proxmox API TLS verification. The PVE nodes serve a self-signed
    certificate, so this is `true` today. Set it back to `false` after the
    cluster gets a trusted certificate.
  EOT
  type        = bool
  default     = true
}

# --- Talos image -------------------------------------------------------------

variable "talos_version" {
  description = <<-EOT
    Talos release to boot, as the git tag. Pinned deliberately: a floating
    version would rebuild nodes on someone else's schedule.

    v1.13.10 is the mature patch of the current-minus-one line. v1.14.0 was 11
    days old when this was chosen, and a `.0` is where the unknown bugs live.
    Raising this is a reviewable change: read the Talos release notes, check the
    Kubernetes and Cilium compatibility window, then plan.
  EOT
  type        = string
  default     = "v1.13.10"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.talos_version))
    error_message = "talos_version must be a release tag such as v1.13.10."
  }
}

variable "talos_iso_checksum" {
  description = <<-EOT
    SHA-256 of `metal-amd64.iso` for `talos_version`, from the release
    `sha256sum.txt`. Proxmox verifies the download against this, so a corrupt or
    substituted image fails at download instead of at boot.

    Change it in the same commit as `talos_version`. A stale checksum is a
    download failure, which is the correct way to fail.
  EOT
  type        = string
  default     = "f50501d54474fc67bc99bb267e20f38db15820e77a03ff791c842dfb90515c57"

  validation {
    condition     = can(regex("^[a-f0-9]{64}$", var.talos_iso_checksum))
    error_message = "talos_iso_checksum must be 64 lowercase hexadecimal characters."
  }
}

variable "iso_datastore" {
  description = <<-EOT
    Datastore that receives the Talos ISO. It must accept `iso` content.
    Discovery on 2026-09-14 found `local` is the only one on either node.
  EOT
  type        = string
  default     = "local"
}

# --- Placement and sizing ----------------------------------------------------

variable "network_bridge" {
  description = <<-EOT
    Bridge for both VM network interfaces.

    No VLAN tag is set anywhere in this layer, and that is deliberate.
    `vmbr0` is NOT VLAN-aware on either node: discovery read `vlan_filtering=0`.
    A tag would be ignored in silence and the VM would land untagged, which
    reads as a network fault rather than a configuration one. R10b makes the
    bridge VLAN-aware; add tags then, not before.
  EOT
  type        = string
  default     = "vmbr0"
}

variable "vm_datastore" {
  description = <<-EOT
    Datastore for the VM disks. It must accept `images`. Discovery found
    `local-lvm` on both nodes: 140.9 GiB free on pve-lenovo, 53.9 GiB on pve-hp.
  EOT
  type        = string
  default     = "local-lvm"
}

variable "control_plane" {
  description = <<-EOT
    The Talos control-plane VM. It sits on `pve-hp`, which has the smaller disk
    (53.9 GiB) and fewer cores (4). A control plane is comparatively static, so
    it is the right guest for the smaller node.
  EOT
  type = object({
    name    = string
    node    = string
    vm_id   = number
    cores   = number
    memory  = number # MiB
    disk_gb = number
  })
  default = {
    name    = "talos-cp-01"
    node    = "pve-hp"
    vm_id   = 100
    cores   = 2
    memory  = 4096
    disk_gb = 40
  }
}

variable "worker" {
  description = <<-EOT
    The Talos worker VM. It sits on `pve-lenovo`, which has the spare cores
    (6 against 4) and nearly three times the disk (140.9 GiB against 53.9 GiB).
    Workloads, container images and volumes land here.
  EOT
  type = object({
    name    = string
    node    = string
    vm_id   = number
    cores   = number
    memory  = number # MiB
    disk_gb = number
  })
  default = {
    name    = "talos-w-01"
    node    = "pve-lenovo"
    vm_id   = 101
    cores   = 4
    memory  = 8192
    disk_gb = 100
  }
}
