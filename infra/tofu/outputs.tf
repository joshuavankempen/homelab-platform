# Outputs for the VM layer.
#
# R12 needs the VM IDs and the node placement to write Talos machine
# configuration. Printing them here means the next layer reads them from state
# rather than from someone's memory of what the web UI showed.

output "talos_vms" {
  description = "The Talos VMs: id, node and size, keyed by role."
  value = {
    for role, vm in proxmox_virtual_environment_vm.talos : role => {
      name       = vm.name
      vm_id      = vm.vm_id
      node       = vm.node_name
      cores      = local.talos_vms[role].cores
      memory_mib = local.talos_vms[role].memory
      disk_gb    = local.talos_vms[role].disk_gb
    }
  }
}

output "talos_version" {
  description = "The Talos release these VMs boot. R12 must match it."
  value       = var.talos_version
}

output "talos_iso_files" {
  description = "The downloaded boot media, keyed by node."
  value = {
    for node, iso in proxmox_download_file.talos_iso :
    node => iso.id
  }
}
