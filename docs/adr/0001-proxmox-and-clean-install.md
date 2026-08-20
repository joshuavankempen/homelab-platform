# ADR-0001 — Keep Proxmox as the hypervisor and clean-install every host

- **Status:** Accepted
- **Decided:** 2026-08-18 (clean install), 2026-08-19 (wipe the SATA pool)
- **Recorded:** 2026-08-20

## Context

The hardware for this project is inherited, not new: two mini PCs and an HP t620
thin client that previously ran an unrelated Minecraft-hosting project. At the
start of this project `pve-lenovo` still held that project's Proxmox install —
hardened by hand over months, with guests, and a 1 TB SATA SSD carrying a ZFS
pool of Minecraft world backups. `pve-hp` had been repurposed as a Bazzite
desktop. The t620 had been provisioned once, in April 2026, and left.

Then the estate moved house. The new network is a flat `192.168.0.0/24`, and the
old install still held a static address on the previous subnet. A full session
(2026-08-18) was spent discovering exactly that: the node was unreachable over
both LAN and Tailscale, the diagnosis was a stale static IP and gateway rather
than a `tailscaled` fault, and every recovery path ended at the physical
console.

Two questions were open at that point. Whether to rescue the existing install or
start clean, and whether a hypervisor belongs under Kubernetes at all — bare
metal Talos on both minis was a genuine option and would have freed the
hypervisor's overhead.

Relevant constraint: Proxmox writes its IP address and FQDN at install time.
Changing them after a cluster exists means editing the corosync ring
configuration, `/etc/hosts` and the node certificates — a known-painful path,
and the reason the network was built before any host was installed.

## Decision

Keep Proxmox as the hypervisor layer, and clean-install everything: PVE 9 on
both minis (to NVMe, addressed directly on the lab VLAN), fresh minimal Debian
13 on the t620 as a corosync qdevice. Nothing from the previous project is
carried over — no guests, no configuration, no hardening. The 1 TB SATA SSD's
ZFS pool is wiped and becomes free space for cluster storage.

## Options considered

| Option                                       | Why it was plausible                                                                                          | Why it lost                                                                                                                                                                                                    |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rescue the existing install, rebuild guests   | Months of hardening already applied; no reinstall evening; the Minecraft archive stays intact for free          | The hardening was undocumented and therefore unauditable — inheriting it means inheriting unknown state into a portfolio piece. Recovery needed physical console access anyway, so it bought no time.            |
| Bare-metal Kubernetes on both minis           | Removes a whole layer and its RAM overhead; Talos is designed to run on metal                                  | Rebuilds stop being reproducible from code: no VM layer means no OpenTofu, and a node rebuild becomes a USB stick and an evening. Also forfeits `vzdump` as the disaster-recovery story and any non-Kubernetes guest. |
| **Keep Proxmox, clean-install everything**    | VM layer is definable in code; snapshots and `vzdump` give a real DR path; nothing unknown is inherited         | **Chosen.**                                                                                                                                                                                                    |
| Keep the SATA ZFS pool, install NVMe-only     | The Minecraft archive survives at zero cost, since the installer never touches the second disk                  | The archive belongs to a retired project that has its own repository. Keeping it costs the 1 TB that cluster storage needs, in exchange for data nothing will read.                                              |

## Consequences

- **Rebuilds are `tofu apply`, not an evening.** The VM layer is declared in
  OpenTofu with the `bpg` Proxmox provider, which is what makes the Talos nodes
  disposable and the whole estate reproducible. This is the main thing the
  hypervisor buys.
- **No rollback to the previous estate.** Accepted deliberately. The old install
  is gone, and the recovery runbook written for it was deleted with it.
- **The install runbook is now tested rather than theoretical.** Provisioning
  all three hosts from one document surfaced four real defects in it — including
  a `sed` on Debian 13's deb822 repo files that was a silent no-op and would
  have left the enterprise repository enabled and the install failing on a 401.
- **`pve-hp` is storage-tight.** Its NVMe is 128 GB, not the 120 GB earlier
  records claimed, and a default ext4 + LVM-thin install leaves roughly 85 GB of
  thin pool. That is adequate for one Talos worker and tight beyond it.
- **Hardening is re-applied deliberately, and differs per host role.** On both
  PVE nodes sshd runs `PermitRootLogin prohibit-password` — **not** `no`, which
  would be a defect: Proxmox needs node-to-node root SSH for migration, `pvesr`
  and `pvecm`. On the qdevice, which needs no inbound root SSH once paired,
  plain `PermitRootLogin no` is correct. Same posture, different value, for a
  reason worth writing down.
- **Two nodes lose no high availability that bare metal would have given.** A
  two-node cluster cannot self-arbitrate either way; quorum comes from a third
  corosync vote (the t620 qdevice), not from the hypervisor choice.
