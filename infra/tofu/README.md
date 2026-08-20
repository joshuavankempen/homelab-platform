# infra/tofu/

OpenTofu definitions for the VM layer: Talos virtual machines on Proxmox — sizes,
disks, VLAN tags, boot media — using the `bpg/proxmox` provider.

This is the layer that makes a node rebuild a command rather than an evening.

Notes:

- **State is remote, not local.** Local state on a laptop is a single point of
  failure for the whole estate. `*.tfstate` is gitignored deliberately.
- **`tofu plan` is the review artifact.** Apply is deliberate and manual; VM
  changes are not auto-reconciled, because a mistaken apply here destroys nodes
  rather than restarting pods.
- **Credentials come from the environment**, never from a committed `.tfvars`.
  `*.tfvars.example` documents the shape without the values.
