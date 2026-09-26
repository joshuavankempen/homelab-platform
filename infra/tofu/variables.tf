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

    Keep this equal to `talosVersion` in `infra/talos/talconfig.yaml` (ADR-0006).
    In maintenance mode the ISO system receives and validates the machine
    config before the installer runs. An older ISO can reject the document kinds
    of a newer config. The first pin, v1.13.10, predated the R12 version
    decision and blocked the first apply-config.

    Raising this is a reviewable change: read the Talos release notes, check the
    Kubernetes and Cilium compatibility window, then plan.
  EOT
  type        = string
  default     = "v1.14.1"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.talos_version))
    error_message = "talos_version must be a release tag such as v1.14.1."
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
  default     = "eb29a0a3c49b19a69a2be11e4ba06cc0837fc61a528af62fea2e803eb9e6d19f"

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
    name        = string
    node        = string
    vm_id       = number
    cores       = number
    memory      = number # MiB
    disk_gb     = number
    mac_address = string
  })
  default = {
    name        = "talos-cp-01"
    node        = "pve-hp"
    vm_id       = 100
    cores       = 2
    memory      = 4096
    disk_gb     = 40
    mac_address = "BC:24:11:14:6F:AD"
  }
}

variable "worker" {
  description = <<-EOT
    The Talos worker VM. It sits on `pve-lenovo`, which has the spare cores
    (6 against 4) and nearly three times the disk (140.9 GiB against 53.9 GiB).
    Workloads, container images and volumes land here.
  EOT
  type = object({
    name        = string
    node        = string
    vm_id       = number
    cores       = number
    memory      = number # MiB
    disk_gb     = number
    mac_address = string
  })
  default = {
    name        = "talos-w-01"
    node        = "pve-lenovo"
    vm_id       = 101
    cores       = 4
    memory      = 8192
    disk_gb     = 100
    mac_address = "BC:24:11:D4:D7:4D"
  }
}
