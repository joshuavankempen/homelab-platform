# Architecture Decision Records

Write one file for each decision that is expensive to reverse. Write one file
also for each decision that a reader would otherwise reconstruct from the commit
history.

The format is [Michael Nygard's](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions.html):
context, decision, consequences. An ADR is immutable once `Accepted`. A change
of mind produces a new ADR that supersedes the old one, so the reasoning trail
survives.

| ADR                                            | Decision                                            | Status   | Decided    |
| ---------------------------------------------- | --------------------------------------------------- | -------- | ---------- |
| [0001](0001-proxmox-and-clean-install.md)      | Keep Proxmox as hypervisor; clean-install everything | Accepted | 2026-08-18 |
| [0002](0002-omada-vlans-er605-routing.md)      | VLANs in Omada, routed by the ER605; no OPNsense VM  | Accepted | 2026-08-16 |
| [0003](0003-talos-linux-over-k3s.md)           | Talos Linux as the Kubernetes OS                     | Accepted | 2026-08-16 |
| [0004](0004-cilium-at-bootstrap.md)            | Cilium as CNI, installed at bootstrap                | Accepted | 2026-08-16 |
| [0005](0005-opentofu-vm-layer-and-remote-state.md) | OpenTofu for the VM layer; GitLab-managed remote state | Accepted | 2026-09-03 |

One ADR is deliberately absent. Storage (local-path + NFS) gets its ADR when the
shape is real rather than planned. The roadmap records that decision for now,
and the numbers depend on the layout of the 1 TB SATA disk.

## How to write a new one

Copy `0000-template.md`. Take the next number. Add a row to the table above. A
decision counts as made only when the ADR exists. That is a working rule of this
project, not a formality: the ADR records the discarded options, and nobody
remembers those a year later.
