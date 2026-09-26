# infra/talos/

This directory holds the Talos machine configuration.
[`talhelper`](https://budimanjojo.github.io/talhelper/) generates it from a
committed `talconfig.yaml`.

_State: `talconfig.yaml` and `talsecret.sops.yaml` exist and render valid
configs for both nodes (Talos v1.14.1, Kubernetes v1.36.5). No config is
applied to a node yet — see the [root README](../../README.md)._

**Talos 1.14 splits the config into documents.** Kube-proxy, the CNI, node
taints and the VIP each moved from the `v1alpha1` document into their own
document kinds. The old fields still work, but a patch on an old field fails
when talhelper also renders the new document. Patch the document kind instead,
and check the rendered output, not the input.

**Secrets are encrypted with sops and age.** The public key is in
[`.sops.yaml`](../../.sops.yaml). `talhelper genconfig` decrypts in memory with
the operator's private key.

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

> **A dry run prints secrets.** `apply-config --dry-run` prints a diff against
> the running config. On a node in maintenance mode, that is the whole config,
> with every CA key in plaintext. Discard the output and keep the exit code:
>
> ```powershell
> talosctl apply-config --insecure -n <ip> --file clusterconfig/<node>.yaml --dry-run | Out-Null
> if ($LASTEXITCODE -eq 0) { 'dry-run OK' } else { 'dry-run FAILED' }
> ```

> **The encrypted secrets file is the one irreplaceable artifact here.** A loss
> of that file means a rebuild of the cluster from scratch, because nobody can
> regenerate the node certificates. Keep it in the password manager as well as
> in git.
