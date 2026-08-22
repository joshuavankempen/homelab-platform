# ADR-0001 — Keep Proxmox as the hypervisor and clean-install every host

- **Status:** Accepted
- **Decided:** 2026-08-18 (clean install), 2026-08-19 (wipe the SATA pool)
- **Recorded:** 2026-08-20

## Context

The hardware for this project is inherited, not new: two mini PCs and an HP t620
thin client. All of it came from an unrelated Minecraft-hosting project. At the
start of this project, `pve-lenovo` still held that project's Proxmox install.
That install had months of manual hardening and several guests, and a 1 TB SATA
SSD in the same host held a ZFS pool of Minecraft world backups. `pve-hp` ran
Bazzite as a desktop. Someone provisioned the t620 once, in April 2026, and then
left it.

Then the estate moved house. The new network is a flat `192.168.0.0/24`, and the
old install still held a static address on the previous subnet. One full session
on 2026-08-18 found exactly that. The node was unreachable over both LAN and
Tailscale. The diagnosis was a stale static IP and gateway, not a `tailscaled`
fault, and every recovery path ended at the physical console.

Two questions were open at that point. First: rescue the existing install, or
start clean. Second: does a hypervisor belong under Kubernetes at all? Bare-metal
Talos on both minis was a genuine option, and it would free the overhead of the
hypervisor.

One constraint is relevant. Proxmox writes its IP address and FQDN at install
time. A change after a cluster exists means an edit to the corosync ring
configuration, to `/etc/hosts` and to the node certificates. That path is known
to be painful, and for that reason the project built the network before any host
install.

## Decision

Keep Proxmox as the hypervisor layer, and clean-install everything. Install PVE 9
on both minis, to NVMe, with an address directly on the lab VLAN. Install fresh
minimal Debian 13 on the t620 as a corosync qdevice. Carry nothing over from the
previous project: no guest, no configuration, no hardening. Wipe the ZFS pool on
the 1 TB SATA SSD, and give the free space to cluster storage.

## Options considered

| Option                                       | Why it was plausible                                                                                          | Why it lost                                                                                                                                                                                                    |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rescue the existing install, rebuild guests   | Months of hardening already applied; no reinstall evening; the Minecraft archive stays intact for free          | The hardening was undocumented and therefore unauditable. To inherit it is to inherit unknown state into a portfolio piece. Recovery needed physical console access anyway, so this option saved no time.        |
| Bare-metal Kubernetes on both minis           | Removes a whole layer and its RAM overhead; Talos runs on metal by design                                      | A rebuild is no longer reproducible from code: no VM layer means no OpenTofu, and a node rebuild costs a USB stick and an evening. It also forfeits `vzdump` as the disaster-recovery path and every non-Kubernetes guest. |
| **Keep Proxmox, clean-install everything**    | The VM layer is definable in code; snapshots and `vzdump` give a real DR path; the estate inherits no unknown state | **Chosen.**                                                                                                                                                                                                    |
| Keep the SATA ZFS pool, install NVMe-only     | The Minecraft archive survives at zero cost, since the installer never touches the second disk                  | The archive belongs to a retired project with its own repository. To keep it costs the 1 TB that cluster storage needs, in exchange for data nobody will read.                                                  |

## Consequences

- **A rebuild is `tofu apply`, not an evening.** OpenTofu declares the VM layer
  with the `bpg` Proxmox provider. That declaration makes the Talos nodes
  disposable and the whole estate reproducible. This is the main thing the
  hypervisor buys.
- **No rollback to the previous estate.** The project accepts this deliberately.
  The old install is gone, and its recovery runbook went with it.
- **The install runbook is now tested rather than theoretical.** One document
  provisioned all three hosts, and that run surfaced four real defects in it. One
  defect was a `sed` on the deb822 repo files of Debian 13. The `sed` was a
  silent no-op. It would leave the enterprise repository enabled, and the install
  would then fail on a 401.
- **`pve-hp` is storage-tight.** Its NVMe is 128 GB, not the 120 GB that earlier
  records claimed. A default ext4 + LVM-thin install leaves roughly 85 GB of thin
  pool. That is adequate for one Talos worker and tight beyond it.
- **The project re-applies hardening deliberately, and the value differs per host
  role.** On both PVE nodes, sshd runs `PermitRootLogin prohibit-password` —
  **not** `no`, which would be a defect: Proxmox needs node-to-node root SSH for
  migration, `pvesr` and `pvecm`. The qdevice needs no inbound root SSH once
  paired, so plain `PermitRootLogin no` is correct there. Same posture, different
  value, for a reason worth a written record.
- **Two nodes lose no high availability that bare metal would give.** A two-node
  cluster cannot self-arbitrate either way. Quorum comes from a third corosync
  vote, the t620 qdevice, not from the hypervisor choice.
