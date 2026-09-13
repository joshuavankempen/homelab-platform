# Changelog

All notable changes to this repository are documented here, in
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. This repository
follows [Semantic Versioning](https://semver.org/).

Infrastructure state that predates this repository is recorded in the ADRs
rather than backfilled here.

## [Unreleased]

### Added

- `infra/tofu/images.tf` — the Talos boot media as a resource. Proxmox fetches
  `metal-amd64.iso` itself through `download-url`, and verifies it against a
  pinned SHA-256, so a corrupt or substituted image fails at download instead of
  at boot. One download per node: `local` is a `dir` datastore on each host, not
  shared. The node list derives from the VM definitions, so a third node needs
  no second edit.
- `infra/tofu/vms.tf` — the two Talos VMs, from one resource with `for_each`.
  `talos-cp-01` on `pve-hp` (2 cores, 4 GiB, 40 GiB) and `talos-w-01` on
  `pve-lenovo` (4 cores, 8 GiB, 100 GiB). Applied 2026-09-14 as VMID 100 and
  101; both boot to Talos maintenance mode.
- `infra/tofu/outputs.tf` — VM IDs, placement and sizes, so R12 reads them from
  state rather than from memory of a web UI screen.
- `infra/tofu/variables.tf` — `talos_version` (`v1.13.10`), its ISO checksum,
  datastores, bridge, and the two VM definitions. Sizes and placement carry
  defaults because discovery measured them; each default records its reasoning.
- `scripts/discover_pve_api.py` — read-only discovery through the Proxmox API.
  It reads the same two environment variables as the provider, so a clean run
  proves the credential that `tofu` will use. It doubles as the first test of
  the `TofuVM` role: a `403` names the endpoint and the missing privilege,
  which is easier to read than the same failure inside a `tofu plan`. The
  client class holds no mutating method, so the script cannot change the
  cluster. `--insecure` is required against the self-signed Proxmox
  certificate, and the script fails closed without it.
- `scripts/discover-pve.sh` — read-only discovery of the Proxmox cluster over
  SSH. It reports quorum, storage and content types, bridge VLAN awareness,
  memory per node, and the VM IDs in use. The VM resources need these facts and
  no file records them. The script changes no state, so it has no `DRY_RUN`
  switch.
- `.gitattributes` — line-ending policy. The workstation sets
  `core.autocrlf = true`, which would give a fresh checkout CRLF and break every
  `.sh` file with `bad interpreter: /usr/bin/env bash^M`.
- `infra/tofu/README.md` — a first-run section, and the two Windows PowerShell
  quoting rules. Both produce errors that name the wrong culprit.
- ADR-0005 — OpenTofu for the VM layer, with GitLab-managed remote state in a
  separate private project, and a dedicated `tofu@pve` user instead of a root
  token.

- `infra/tofu/versions.tf` — OpenTofu `>= 1.6.0`, and `bpg/proxmox` pinned to
  patch releases of `0.111.1`. The `http` backend block is empty on purpose:
  it is a partial configuration, and it fails closed without
  `-backend-config`.
- `infra/tofu/providers.tf` — the Proxmox connection. The endpoint and the API
  token come from the environment only.
- `infra/tofu/variables.tf` — `proxmox_insecure_tls`, which defaults to
  `false`.
- `infra/tofu/backend.hcl.example` — the state addresses, without the private
  project ID.
- Repository scaffold: `apps/`, `clusters/homelab/`, `infra/tofu/`,
  `infra/talos/`, `docs/`.
- ADR-0001 — keep Proxmox as hypervisor and clean-install every host.
- ADR-0002 — VLANs defined in Omada and routed by the gateway; no firewall VM.
- ADR-0003 — Talos Linux as the Kubernetes OS.
- ADR-0004 — Cilium as the CNI, installed at bootstrap.
- `docs/network.md` — VLAN plan, switch configuration of record, verification
  commands, and the failure modes worth knowing in advance.
- `.gitignore` covering rendered Talos machine configs, kubeconfig/talosconfig,
  OpenTofu state and unsealed secrets.

### Changed

- `infra/tofu/vms.tf` — pin the MAC address of each VM, using the values
  Proxmox already generated. Without the pin, a rebuilt VM returns with a new
  random MAC, recorded only in state, and anything keyed on it breaks: DHCP
  reservations, firewall rules, DNS entries. The addresses become `.21` and
  `.22` by Omada reservation, so the maintenance-mode address matches the one
  the Talos machine config sets in R12.
- ADR-0005 — added *The `TofuVM` role*: the full privilege list, the reason for
  each entry, and what is deliberately absent. `VM.Monitor` does not exist on
  PVE 9. `SDN.Use` and `SDN.Audit` are required because PVE 9 models a local
  Linux bridge as the SDN zone `localnetwork`, so without them the token cannot
  see `vmbr0` and a plan would fail while attaching a NIC.
- ADR-0005 — amended with *Where the layer executes*. The original named the
  tool, the state location and the auth model, but never the execution host.
  The layer runs from a human-operated workstation, because it creates the first
  VMs and so cannot run inside its own output. Records the rejected admin VM and
  in-cluster runner, and permits a read-only `tofu plan` on a merge request
  while apply stays manual. Also records the expired upstream GPG key for
  `bpg/proxmox`, which a future OpenTofu version will treat as fatal.
- `infra/tofu/versions.tf` — corrected the state-token comment. The token is a
  personal access token with granular permissions (`Create`, `Read`, `Lock`
  under CI/CD → Terraform State), not a legacy token with scope `api`.
- `.gitignore` now ignores `backend.hcl`, and tracks `backend.hcl.example`.
  `backend.hcl` names a private project, and this repository is public.

### Fixed

- `.gitignore` no longer ignores `.terraform.lock.hcl`. The lock file pins the
  exact provider version and its checksums. An ignored lock file lets two
  machines resolve two different providers, so a run stops being
  reproducible.
