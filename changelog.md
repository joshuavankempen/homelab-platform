# Changelog

All notable changes to this repository are documented here, in
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. This repository
follows [Semantic Versioning](https://semver.org/).

Infrastructure state that predates this repository is recorded in the ADRs
rather than backfilled here.

## [Unreleased]

### Added

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
