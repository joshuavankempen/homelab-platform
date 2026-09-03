# Changelog

All notable changes to this repository are documented here, in
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. This repository
follows [Semantic Versioning](https://semver.org/).

Infrastructure state that predates this repository is recorded in the ADRs
rather than backfilled here.

## [Unreleased]

### Added

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

- `.gitignore` now ignores `backend.hcl`, and tracks `backend.hcl.example`.
  `backend.hcl` names a private project, and this repository is public.

### Fixed

- `.gitignore` no longer ignores `.terraform.lock.hcl`. The lock file pins the
  exact provider version and its checksums. An ignored lock file lets two
  machines resolve two different providers, so a run stops being
  reproducible.
