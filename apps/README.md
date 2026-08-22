# apps/

Keep one directory per application. Each one holds Helm values, kustomize
overlays, and any supporting manifest. Nobody applies a file here directly. The
Argo CD applications in [`../clusters/homelab/`](../clusters/homelab/) point at
these paths, so a merge here deploys the change.

_State: this directory holds no application yet. The convention below describes
the target layout — see the [root README](../README.md)._

Layout convention:

```text
apps/<name>/
├── values.yaml           # Helm values, if the app is a chart
├── kustomization.yaml    # if the app is plain manifests
└── secrets/              # SealedSecrets only; never plaintext
```

These rules apply to every file in this directory:

- **Pin every chart version and image version.** An unpinned chart makes a sync
  non-reproducible, and that defeats the reason to commit it.
- **Seal every secret before you commit it.** A file deletion does not repair a
  plaintext secret in the git history.
- **Expose an app internally by default.** Public exposure is an explicit
  decision per app. Route it through the tunnel; never open a port.
