# The Talos virtual machines.
#
# Two VMs, one per node, as ADR-0005 decides. Sizes and placement come from the
# 2026-09-14 discovery, and the reasoning lives in `variables.tf` beside each
# value.
#
# These VMs are deliberately empty. This layer creates the machines and gives
# them boot media; it does not configure Talos. Machine configuration, the
# cluster secret and `talosctl bootstrap` belong to R12, so that a mistake in
# cluster config never proposes to delete a disk.
#
# A destroy here removes a cluster node and its disk. The cluster has two nodes
# and nowhere to drain to, so read every plan before you apply it.

locals {
  # Both VMs share every setting that is not size or placement. Writing them
  # once keeps the two definitions honest: a change to the disk interface or the
  # machine type cannot drift between control plane and worker.
  talos_vms = {
    control_plane = var.control_plane
    worker        = var.worker
  }
}

resource "proxmox_virtual_environment_vm" "talos" {
  for_each = local.talos_vms

  name      = each.value.name
  node_name = each.value.node
  vm_id     = each.value.vm_id

  description = join(" ", [
    "Talos ${var.talos_version} ${each.key == "control_plane" ? "control plane" : "worker"}.",
    "Managed by OpenTofu in homelab-platform, infra/tofu.",
    "Do not edit in the web UI: the next apply reverts it.",
  ])
  tags = ["talos", "opentofu", each.key == "control_plane" ? "control-plane" : "worker"]

  # Start both VMs on boot. `onboot` is a general option, so `VM.Config.Options`
  # covers it.
  on_boot = true

  # No `startup` block, and this is a deliberate trade rather than an omission.
  #
  # Boot ORDER is not a VM permission in Proxmox. `PVE/API2/Qemu.pm` reads:
  #
  #     # special case for startup since it changes host behaviour
  #     if ($opt eq 'startup') {
  #         $rpcenv->check_full($authuser, "/", ['Sys.Modify']);
  #     }
  #
  # `Sys.Modify` on `/` also grants rewriting node network configuration, DNS
  # and time. PVE demands it here exactly because startup order changes how the
  # host behaves. The benefit is that a worker does not log failed joins for the
  # first minute after a power cut. That is not worth the grant, so the layer
  # keeps the minimal role and gives up the ordering.
  #
  # Both VMs still start on boot, in no guaranteed order. Talos tolerates it:
  # a worker retries until the control plane answers.
  #
  # If ordering is ever needed, set it by hand in the web UI. This layer does
  # not manage the field, so a manual value persists and causes no drift.

  # Without the guest agent there is no graceful shutdown, so a destroy would
  # wait for a VM that never stops. This matters only if `prevent_destroy` below
  # is deliberately lifted, which is exactly when a hung destroy is unwelcome.
  stop_on_destroy = true

  # `host` passes the physical CPU through, which Talos and Kubernetes both
  # benefit from. The two nodes have different CPUs (i5-9500T and i3-8300T), so
  # this rules out live migration between them. That is an accepted trade: the
  # cluster has no shared storage, so migration was never available anyway.
  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
    # No ballooning. Kubernetes schedules against a memory figure it believes is
    # real, and a balloon that reclaims memory under host pressure causes the
    # kubelet to evict pods for reasons invisible inside the guest.
    floating = 0
  }

  # `iothread` only takes effect on a `virtio-scsi-single` controller. The
  # provider defaults to `virtio-scsi-pci`, where Proxmox ignores the flag: the
  # plan would show `iothread = true` while the VM ran without it. Set the
  # controller so the disk setting means what it says.
  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = var.vm_datastore
    interface    = "scsi0"
    size         = each.value.disk_gb
    file_format  = "raw"
    ssd          = true
    discard      = "on"
    iothread     = true
  }

  # `ide3` is the provider default, stated here because `boot_order` below names
  # it. Leaving it implicit would make the two silently disagree after an
  # upgrade that changed the default.
  cdrom {
    file_id   = proxmox_download_file.talos_iso[each.value.node].id
    interface = "ide3"
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"

    # Pin the MAC. Proxmox generates a random one otherwise, recorded only in
    # state, so a rebuilt VM would come back with a different address. Anything
    # keyed on the MAC — a DHCP reservation, a firewall rule, a DNS entry —
    # would then break, and the VM would look like a new machine on the network.
    #
    # The values are the addresses Proxmox generated on 2026-09-14. Pinning what
    # already exists means this change is a no-op against the running VMs.
    mac_address = each.value.mac_address

    # No `vlan_id`. `vmbr0` is not VLAN-aware on either node, so a tag would be
    # ignored in silence. See `network_bridge` in variables.tf, and R10b.
  }

  operating_system {
    type = "l26"
  }

  # No `agent` block. The QEMU guest agent needs the `qemu-guest-agent` system
  # extension, which vanilla Talos images do not carry: it comes from the Talos
  # Image Factory. Enabling the agent without it makes Proxmox wait for a guest
  # that never answers, so every apply and every shutdown stalls until timeout.
  # Revisit with a Factory image, not by flipping this on.

  # Boot from disk first, then the ISO. Talos installs to disk during R12; after
  # that, disk-first makes a reboot come up on the installed system while the
  # ISO stays attached as a rescue path.
  boot_order = ["scsi0", "ide3"]

  # Two guards, because they cover different doors.
  #
  # `protection` sets the PVE flag on the VM itself. Proxmox then refuses to
  # remove the VM or its disks from every path: the web UI, `qm destroy`, the
  # API, and this provider. It is the only one of the two that binds a human
  # clicking Remove in the browser.
  #
  # Deliberately destroying a VM therefore takes two steps: set this to `false`
  # and apply, then destroy. That is the point. A node rebuild should cost one
  # more commit than a typo does.
  protection = true

  # `prevent_destroy` is OpenTofu's own guard, and it stops a plan before it
  # ever reaches Proxmox. It catches the more likely accident: a rename, or a
  # changed argument that forces replacement, which would otherwise delete a
  # cluster node to recreate it. This cluster has two nodes and nowhere to drain
  # to, so a replacement is an outage.
  lifecycle {
    prevent_destroy = true
  }
}
