# homelab-platform

This repository defines a two-node Kubernetes platform on second-hand mini PCs.
OpenTofu defines the hypervisor VMs. Talos machine configs define the immutable
nodes. Argo CD reconciles everything above them. Nobody configures anything by
hand. Where a manual step exists, an ADR explains why.

<!-- Badges (GitLab pipeline, Argo sync) land with the CI milestone. -->

> **Status — 2026-08-20.** The platform layer is built and verified. Two Proxmox
> nodes form a cluster on their own VLAN, with a three-vote corosync quorum. The
> Kubernetes layer is next. No Talos VMs exist yet. Sections below marked
> _Planned_ are designed but not yet built. This README tracks reality, not
> intent.

**Development happens on GitLab; this GitHub repository is a one-way push
mirror.** Pipelines and merge requests live upstream. This copy shows no
activity beyond the mirrored commits. A pull request against this copy would
not get a review: the next mirror push would overwrite it first.

---

## Why this exists

Three reasons, in order of how much they shaped the decisions:

1. **To run real infrastructure the way production teams run it** —
   declaratively, reviewable, and reproducible — on hardware small enough that
   mistakes stay cheap. Recovery becomes a rebuild, not an incident.
2. **To learn the layers rather than the abstractions.** Talos over k3s, Cilium
   over Flannel, and a manual first bootstrap are each a deliberate difficulty
   ([ADR-0003](docs/adr/0003-talos-linux-over-k3s.md),
   [ADR-0004](docs/adr/0004-cilium-at-bootstrap.md)).
3. **To be evidence.** For a reader, the interesting artifact is not that a
   cluster runs. It is the decision trail in [`docs/adr/`](docs/adr/): the
   rejected options, the constraints, and the failure modes the project found
   when it hit them.

The estate is deliberately zero-purchase and zero-subscription: inherited
hardware, free tiers, an already-owned domain, roughly 30 W of electricity.

## Architecture

```mermaid
graph TD
    subgraph GIT["Git (this repository)"]
        TOFU["infra/tofu — VM definitions"]
        TALOS["infra/talos — machine configs"]
        CLUSTER["clusters/homelab — Argo applications"]
        APPS["apps/* — Helm values, manifests"]
    end

    subgraph HW["Two mini PCs + a thin client, on their own VLAN"]
        PVE1["pve-lenovo — Proxmox<br/>control plane + storage"]
        PVE2["pve-hp — Proxmox<br/>worker"]
        QD["qdevice — third corosync vote"]
    end

    subgraph K8S["Kubernetes (Talos)"]
        CP["control-plane + worker"]
        W["worker"]
        ARGO["Argo CD"]
        WL["workloads: DNS, monitoring, media, site"]
    end

    TOFU -->|tofu apply| PVE1
    TOFU -->|tofu apply| PVE2
    TALOS -->|talhelper| CP
    TALOS -->|talhelper| W
    PVE1 --- QD
    PVE2 --- QD
    PVE1 --> CP
    PVE2 --> W
    CP --- W
    CLUSTER -->|watched by| ARGO
    APPS -->|watched by| ARGO
    ARGO -->|reconciles| WL
    CP --> ARGO
```

## Stack

| Layer                | Choice                                                        | State   |
| -------------------- | ------------------------------------------------------------- | ------- |
| Hypervisor           | Proxmox VE 9 ([ADR-0001](docs/adr/0001-proxmox-and-clean-install.md)) | Built   |
| Cluster quorum       | Corosync qdevice on a third box (three votes)                  | Built   |
| Network segmentation | VLANs in Omada, routed by the gateway ([ADR-0002](docs/adr/0002-omada-vlans-er605-routing.md)) | Built (lab VLAN) |
| VM provisioning      | OpenTofu, `bpg/proxmox` provider                               | Planned |
| Kubernetes OS        | Talos Linux via `talhelper` ([ADR-0003](docs/adr/0003-talos-linux-over-k3s.md)) | Planned |
| CNI                  | Cilium — kube-proxy replacement, LB-IPAM, Hubble ([ADR-0004](docs/adr/0004-cilium-at-bootstrap.md)) | Planned |
| GitOps               | Argo CD, app-of-apps                                          | Planned |
| Secrets              | SealedSecrets                                                 | Planned |
| Storage              | local-path on workers; NFS from a ZFS dataset for bulk data     | Planned |
| Ingress and TLS      | Internal ingress + cert-manager with DNS-01                    | Planned |
| Public exposure      | Cloudflare Tunnel — no port forwards, no public home address    | Planned |
| Internal DNS         | Pi-hole in-cluster on a stable lab VIP                         | Planned |
| Observability        | kube-prometheus-stack, plus Hubble from bootstrap               | Planned |
| CI                   | GitLab CI, self-hosted runner in-cluster                        | Planned |

## How a change flows

```text
commit  ->  GitLab CI                    ->  Argo CD              ->  cluster
            lint, validate manifests,        detects drift from       reconciled,
            helm template / kustomize        the committed state      health reported
            diff, tofu plan
```

Nobody applies anything by hand. A change follows one of three paths:

- A workload change is a merge request against [`apps/`](apps/).
- A change to the cluster's application set is a merge request against
  [`clusters/homelab/`](clusters/homelab/).
- A change to the machines themselves is a merge request against
  [`infra/`](infra/), followed by a deliberate, manual apply.

By design, reconciliation for node and VM changes stays manual.

## Repository structure

```text
homelab-platform/
├── apps/                 # per-application Helm values and manifests
├── clusters/homelab/     # Argo CD applications (app-of-apps root)
├── infra/
│   ├── tofu/             # OpenTofu: Proxmox VMs, disks, VLAN tags
│   └── talos/            # talhelper config; rendered output is gitignored
├── docs/
│   ├── adr/              # architecture decision records
│   └── network.md        # VLAN plan, switch config, verification
└── changelog.md
```

## Scope

**This repository does:**

- define the VM layer, the Kubernetes nodes, and every workload as code
- document the decisions and the network the platform depends on
- deploy through GitOps reconciliation rather than manual application

**This repository does not:**

- hold a secret in plaintext — the project seals every secret, and
  `.gitignore` excludes the rendered node configs that hold the cluster CA
- manage the household network beyond the lab VLAN it needs
- claim high availability: two nodes, one control plane, single-homed power

## Runtime layout

| Node         | Hardware                        | Role                                          |
| ------------ | ------------------------------- | --------------------------------------------- |
| `pve-lenovo` | Lenovo M920q, i5-9500T, 16 GB   | Proxmox; Talos control-plane + worker; storage |
| `pve-hp`     | HP ProDesk 400 G4, i3-8300T, 16 GB | Proxmox; Talos worker                       |
| qdevice      | HP t620 thin client, 4 GB       | Third corosync vote only                       |

All three sit on the lab VLAN with static addresses. Remote access uses a mesh
VPN with key-only SSH. The project publishes no service to the internet, except
through Cloudflare Tunnel. See [`docs/network.md`](docs/network.md).

## Validation

The project verifies the platform layer. It does not merely assume the platform
works. Current checks:

```bash
pvecm status                                    # 3 expected votes, Quorate
grep -E 'ring0_addr' /etc/pve/corosync.conf     # ring pinned to the lab VLAN
sshd -T | grep -iE 'permitrootlogin|passwordauthentication'
smartctl -H /dev/nvme0n1                        # disk health
```

If `sshd -T` reports `permitrootlogin without-password`, that is the older
label for `prohibit-password`. This value is correct on a Proxmox node: the
node needs node-to-node root SSH for migration and cluster operations. If a
Proxmox node reports `permitrootlogin no`, that is a defect, not extra
hardening. The qdevice needs no inbound root SSH, so plain `no` is correct
there.

## Conventions

- **Commits follow [Conventional Commits](https://www.conventionalcommits.org/):**
  `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`, with an optional scope —
  `feat(cilium): …`. This keeps changelog generation available later.
- **`main` is the only mirrored branch.** Work happens on branches, then lands
  on `main`. The mirror carries protected branches only, so the public copy
  shows reviewed state, never work in progress. That is why this repository
  has exactly one branch.
- **Decisions get an ADR.** A decision counts as made only when the ADR
  exists. See [`docs/adr/README.md`](docs/adr/README.md).
- **Notable changes go in [`changelog.md`](changelog.md)** in Keep a Changelog
  format.

## Versioning

Semantic Versioning applies here:

- A breaking change increments MAJOR.
- A backward-compatible addition increments MINOR.
- A fix increments PATCH.

See [`changelog.md`](changelog.md) for history.

## Limitations

Honest ones, not placeholders:

- **No high availability.** The design has two nodes and one control plane.
  The third corosync vote protects only against split-brain, not against a
  failure of the control-plane node.
- **No replicated storage.** Longhorn and Rook-Ceph both need three nodes. The
  project backs up workload data on local-path and NFS. It does not replicate
  that data.
- **One node is storage-tight.** The worker's NVMe leaves roughly 85 GB of
  usable thin pool. That is adequate for one Talos worker, and little else.
- **Single-homed power, no UPS.** An outage takes the whole estate down, and
  one host's firmware requires manual intervention to come back up after loss
  of AC.
- **Segmentation is partly organisational.** The lab VLAN exists, but it still
  lacks the inter-VLAN ACLs that enforce it
  ([ADR-0002](docs/adr/0002-omada-vlans-er605-routing.md)).

## License

MIT — see [`LICENSE`](LICENSE). This repository's configuration is specific to
this estate. Reuse the ADRs and the runbook structure instead.
