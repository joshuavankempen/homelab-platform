# infra/talos/

This directory holds the Talos machine configuration.
[`talhelper`](https://budimanjojo.github.io/talhelper/) generates it from a
committed `talconfig.yaml`.

_State: `talconfig.yaml` and the encrypted secrets file are not committed yet.
The Kubernetes layer is planned — see the [root README](../../README.md)._

**What the repository commits:** `talconfig.yaml` and the encrypted secrets
file. `talconfig.yaml` is the declarative description of the cluster: node
roles, addresses, disks, system extensions, and the kube-proxy-replacement
settings for Cilium.

**What the repository excludes:** the rendered per-node configs, `talosconfig`,
and `kubeconfig`. The rendered output holds the cluster CA private key, so
`.gitignore` excludes `clusterconfig/` — see
[ADR-0003](../../docs/adr/0003-talos-linux-over-k3s.md).

Typical flow:

```bash
talhelper genconfig                      # render into clusterconfig/
talosctl apply-config --nodes <ip> --file clusterconfig/<node>.yaml
```

> **The encrypted secrets file is the one irreplaceable artifact here.** A loss
> of that file means a rebuild of the cluster from scratch, because nobody can
> regenerate the node certificates. Keep it in the password manager as well as
> in git.
