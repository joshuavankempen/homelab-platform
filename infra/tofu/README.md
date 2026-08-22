# infra/tofu/

This directory holds the OpenTofu definitions for the VM layer. They define the
Talos virtual machines on Proxmox: sizes, disks, VLAN tags, and boot media. They
use the `bpg/proxmox` provider.

_State: this directory holds no OpenTofu configuration yet. The notes below
describe the target layout — see the [root README](../../README.md)._

This is the layer that makes a node rebuild a command rather than an evening.

Notes:

- **The state is remote, not local.** Local state on a laptop is a single point
  of failure for the whole estate. `.gitignore` excludes `*.tfstate`
  deliberately.
- **`tofu plan` is the review artifact.** An apply is deliberate and manual. No
  automation reconciles a VM change, because a mistaken apply here destroys a
  node rather than restarts a pod.
- **Credentials come from the environment**, never from a committed `.tfvars`
  file. `*.tfvars.example` documents the shape without the values.
