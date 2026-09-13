# Changelog

All notable changes to this repository are documented here, in
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. This repository
follows [Semantic Versioning](https://semver.org/).

Infrastructure state that predates this repository is recorded in the ADRs
rather than backfilled here.

## [Unreleased]

### Added

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

### Changed

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

- `.gitignore` now ignores `backend.hcl`, and tracks `backend.hcl.example`.
  `backend.hcl` names a private project, and this repository is public.

### Fixed

- `.gitignore` no longer ignores `.terraform.lock.hcl`. The lock file pins the
  exact provider version and its checksums. An ignored lock file lets two
  machines resolve two different providers, so a run stops being
  reproducible.
