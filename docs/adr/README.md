# Architecture Decision Records

One file per decision that would be expensive to reverse or that a reader would
otherwise have to reconstruct from commit history.

Format is [Michael Nygard's](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions.html):
context, decision, consequences. An ADR is immutable once `Accepted` — a changed
mind produces a new ADR that supersedes it, so the reasoning trail survives.

| ADR                                            | Decision                                            | Status   | Decided    |
| ---------------------------------------------- | --------------------------------------------------- | -------- | ---------- |
| [0001](0001-proxmox-and-clean-install.md)      | Keep Proxmox as hypervisor; clean-install everything | Accepted | 2026-08-18 |
| [0002](0002-omada-vlans-er605-routing.md)      | VLANs in Omada, routed by the ER605; no OPNsense VM  | Accepted | 2026-08-16 |
| [0003](0003-talos-linux-over-k3s.md)           | Talos Linux as the Kubernetes OS                     | Accepted | 2026-08-16 |
| [0004](0004-cilium-at-bootstrap.md)            | Cilium as CNI, installed at bootstrap                | Accepted | 2026-08-16 |

Deliberately not yet written: storage (local-path + NFS) gets its ADR when the
shape is real rather than planned — the decision is recorded in the roadmap and
the numbers depend on how the 1 TB SATA is carved up.

## Writing a new one

Copy `0000-template.md`, take the next number, add a row above. The decision is
not made until the ADR exists — that is a working rule of this project, not a
formality: the ADR is where the discarded options are recorded, and those are
the part nobody remembers a year later.
