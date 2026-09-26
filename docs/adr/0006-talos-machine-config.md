# ADR-0006 — Pin the Talos and Kubernetes versions, and patch the Talos 1.14 documents

- **Status:** Accepted
- **Decided:** 2026-09-26 (the untaint: 2026-09-22)
- **Recorded:** 2026-09-26

## Context

The machine config in [`infra/talos/`](../../infra/talos/) is the last input
before the nodes install Talos to disk. After that step, a change of Talos
version, Kubernetes version or installer image is an upgrade on a live cluster,
not an edit to a file. Four questions needed an answer before the first
`apply-config`.

**Versions.** Talos 1.14.0 shipped on 2026-08-27, and Talos 1.13 left community
support on that date. The default Kubernetes version of Talos 1.14.1 is v1.37.0.
Cilium is the CNI ([ADR-0004](0004-cilium-at-bootstrap.md)), and Cilium 1.20 is
tested against Kubernetes 1.33–1.36 only. A CNI outside its tested range is the
single component that can take down the whole cluster network.

**Installer image.** The stock Talos installer holds no QEMU guest agent. Without
the agent, Proxmox cannot shut a VM down cleanly or read its addresses, and the
OpenTofu layer ([ADR-0005](0005-opentofu-vm-layer-and-remote-state.md)) keeps
its `agent` block off until the nodes run an image that has one.

**Scheduling capacity.** The cluster has two nodes: one control plane and one
worker. The control plane VM has 2 vCPU and 4 GiB, and the worker VM has 4 vCPU
and 8 GiB. With the default `NoSchedule` taint, a third of that capacity runs
only the control plane.

**Config structure.** Talos 1.14 moves kube-proxy, the CNI, node taints and the
VIP out of the `v1alpha1` document into separate document kinds. The old fields
still parse. A patch on an old field fails, however, when talhelper also renders
the new document for the same setting. The first two render cycles failed on
exactly this.

## Decision

1. **Pin Talos v1.14.1 and Kubernetes v1.36.5**, and override the Talos default
   of v1.37. Move to Kubernetes 1.37 when a Cilium release lists it as tested.
2. **Install from the Image Factory**, with the schematic
   `ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515`. It adds
   `siderolabs/qemu-guest-agent` and nothing else.
3. **Remove the control-plane taint** with `allowSchedulingOnControlPlanes:
   true`. Both nodes run workloads, and the pool is 6 vCPU and 12 GiB.
4. **Patch the document kind, never the legacy field.** The kube-proxy patch
   targets `KubeProxyConfig` with `enabled: false`, under `controlPlane`,
   because Talos accepts that document on control plane machines only. Review
   the rendered output, not `talconfig.yaml`, to confirm what a node receives.

## Options considered

### Versions

| Option                            | Why it was plausible                                   | Why it lost                                                                                              |
| --------------------------------- | ------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- |
| **Talos 1.14.1 + Kubernetes 1.36** | Supported Talos, and a Kubernetes that Cilium tests     | **Chosen.** It is the newest pair inside every support window.                                           |
| Talos 1.14.1 + Kubernetes 1.37    | The Talos default, so no override to maintain          | Cilium 1.20 does not test 1.37. The CNI owns the whole dataplane, so an untested pair risks all of it.   |
| Talos 1.13.x + Kubernetes 1.36    | The older config layout; no multi-document surprises    | No community support since 2026-08-27. winget also has no 1.13 `talosctl` client.                        |

### Installer image

| Option                         | Why it was plausible                                  | Why it lost                                                                                         |
| ------------------------------ | ----------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| **Image Factory, guest agent** | Clean Proxmox shutdown and address reporting          | **Chosen.** One extension, and the schematic ID makes the image reproducible.                       |
| Stock installer                | No dependency on the Factory service                  | No guest agent, so a VM shutdown is a hard stop and the tofu `agent` block stays off permanently.  |
| Factory, more extensions       | iSCSI or other tools for later storage work           | No current workload needs them. Add them with a new schematic when a real need exists.             |

### Control-plane taint

| Option               | Why it was plausible                                | Why it lost                                                                                  |
| -------------------- | --------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| **Untainted**        | Raises the schedulable pool from 4 to 6 vCPU and from 8 to 12 GiB | **Chosen.** The capacity gain is large and the cluster has no multi-tenant workload. |
| Tainted (default)    | Isolates etcd and the API server from workloads     | A third of the hardware runs only the control plane, and one worker is a single point of failure. |

### Config structure

| Option                          | Why it was plausible                               | Why it lost                                                                                         |
| ------------------------------- | -------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| **Patch the document kind**     | Matches the Talos 1.14 model and talhelper output  | **Chosen.** It is the only form that renders without conflict.                                      |
| Patch the legacy field          | Most published examples use it                     | It conflicts with the `KubeProxyConfig` document that talhelper renders. The render fails.           |
| `talosctl gen config` by hand   | No talhelper version lag                           | It loses the declarative per-node file and the sops-encrypted secrets flow.                          |

## Consequences

- **The Kubernetes version needs a manual review at every Cilium release.** The
  pin does not expire by itself. A Cilium release that tests 1.37 is the trigger
  for an upgrade.
- **The cluster depends on the Image Factory for installs and upgrades.** An
  unreachable Factory blocks a reinstall. The schematic ID is in the rendered
  config, so the image stays reproducible while the Factory runs.
- **The control plane shares resources with workloads.** A memory-hungry
  workload can starve etcd on cp-01. Resource limits on workloads are therefore
  a requirement, not a nicety, from the first Argo CD application onward.
- **Published examples mislead for this Talos version.** Most examples patch
  legacy fields. Every new patch needs a check against the rendered output.
- **Absence of a document is assumed to mean "not deployed".** No
  `KubeFlannelCNIConfig` is rendered, so no flannel should deploy. The Talos
  docs do not state this outright. Bootstrap day checks `talosctl get manifests`
  for flannel before Cilium goes in.
- **talhelper 3.1.17 warns that v1.14.1 "might not be compatible".** Both
  configs validate, and the embedded Talos library knows the 1.14 documents, so
  the project accepts the warning as a known gap until a newer talhelper release.
