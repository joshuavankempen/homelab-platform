# ADR-0003 — Talos Linux as the Kubernetes OS

- **Status:** Accepted
- **Decided:** 2026-08-16
- **Recorded:** 2026-08-20

## Context

Kubernetes runs as VMs on Proxmox ([ADR-0001](0001-proxmox-and-clean-install.md)):
one control-plane-plus-worker on `pve-lenovo`, one worker on `pve-hp`. That
leaves one choice open: the operating system inside those VMs.

This repository has one premise. Git defines the estate, and machines reconcile
it. A node that an operator configures over SSH breaks that premise. Such a node
becomes the place where undocumented state accumulates, which is exactly the
problem [ADR-0001](0001-proxmox-and-clean-install.md) exists to escape.

The project also has a stated learning objective. The builder must understand the
Kubernetes control plane, not merely run `kubectl`.

## Decision

**Talos Linux.** `talhelper` generates the machine configurations from a
committed `talconfig.yaml`, and the secrets stay out of the repository. k3s on
Debian stays documented as the fallback if Talos proves unworkable.

## Options considered

| Option              | Why it was plausible                                                                                                     | Why it lost                                                                                                                                                                        |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Talos Linux**     | Immutable, API-driven, no SSH and no package manager: the node is a declarative artifact like everything else in the repo  | **Chosen.** An upgrade is an image swap with rollback, and the attack surface is minimal because almost nothing sits on disk to attack.                                              |
| k3s on Debian       | Fastest path to a working cluster; a normal Linux box underneath when something breaks; every tutorial assumes it          | The "normal Linux box" is the problem — mutable state outside Git, and the same convenience that helps a debug session also lets configuration drift in unrecorded.                  |
| kubeadm on Debian   | The reference implementation; closest to what certifications and many jobs use                                             | All of the drift problem of k3s plus considerably more assembly. The learning it forces is real, but it lands on the one layer that must work before anything else can be built.     |

## Consequences

- **Use `talosctl` to debug, not `ssh`.** The node has no shell. This is the
  largest day-to-day cost and a genuine learning curve — name it here rather than
  meet it during an incident.
- **Every node change is a machine-config change.** Each change is slower. In
  exchange, a reviewer reads the node state as a diff, and a rebuild reproduces
  it.
- **Some Helm charts assume a conventional distribution.** A chart that needs
  hostPath mounts, kernel modules or host packages needs a Talos system extension
  in the image. Expect this with storage components and monitoring components.
- **`talhelper` becomes a dependency of cluster recovery.** The rendered configs
  hold the cluster CA, so `.gitignore` excludes them, and a rebuild therefore
  needs the tool plus the encrypted secrets file. A lost secrets file means a
  rebuild of the cluster from scratch. Keep that file in the password manager,
  not only on disk.
