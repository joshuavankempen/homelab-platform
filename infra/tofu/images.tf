# Talos boot media.
#
# ADR-0005 puts the boot media in R11 scope, so the image is a resource rather
# than something uploaded by hand. A hand-uploaded ISO is invisible to Git and
# to the next person, and it is the first thing missing after a node rebuild.
#
# One download per node. The nodes do not share storage: discovery on
# 2026-09-14 found `local` is a `dir` datastore on each host, not shared, so an
# ISO on pve-lenovo is absent on pve-hp. Downloading to both keeps either node
# able to boot either VM, which is what makes a rebuild cheap.
#
# Proxmox fetches the file itself, through the `download-url` endpoint. That is
# why the role needs `Sys.AccessNetwork` and `Datastore.AllocateTemplate`: the
# workstation never holds the image.

locals {
  # Both VMs boot the same image. Deriving the node list from the VM definitions
  # keeps the two in step: adding a VM on a third node downloads the ISO there
  # too, with no second edit.
  talos_nodes = toset([
    var.control_plane.node,
    var.worker.node,
  ])

  talos_iso_url = join("/", [
    "https://github.com/siderolabs/talos/releases/download",
    var.talos_version,
    "metal-amd64.iso",
  ])

  # Name the file for its version. `talos-v1.14.1-metal-amd64.iso` says what it
  # is in `qm config` output and in the storage browser, where a bare
  # `metal-amd64.iso` would not. It also lets two versions coexist during an
  # upgrade, instead of one silently replacing the other.
  talos_iso_filename = "talos-${var.talos_version}-metal-amd64.iso"
}

resource "proxmox_download_file" "talos_iso" {
  for_each = local.talos_nodes

  node_name    = each.value
  datastore_id = var.iso_datastore
  content_type = "iso"

  url       = local.talos_iso_url
  file_name = local.talos_iso_filename

  # Verify the image rather than trust the transport. A corrupt or substituted
  # ISO then fails at download, where the error names the cause, instead of at
  # boot, where it looks like broken hardware.
  checksum           = var.talos_iso_checksum
  checksum_algorithm = "sha256"

  # Do not re-download an image that is already present and correct. Without
  # this, a plan proposes to replace the file whenever Proxmox reports it
  # differently, which is noise in a review that must stay readable.
  overwrite = false

  # A version change renames the file, so tofu replaces this resource. The
  # default order deletes the old ISO first, while both VMs still reference it.
  # Create the new ISO first, move the cdrom, then delete the old one.
  lifecycle {
    create_before_destroy = true
  }
}
