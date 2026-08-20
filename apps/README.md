# apps/

One directory per application: Helm values, kustomize overlays, and any
supporting manifests. Nothing here is applied directly — Argo CD applications in
[`../clusters/homelab/`](../clusters/homelab/) point at these paths, so a merge
here is what deploys.

Layout convention:

```text
apps/<name>/
├── values.yaml           # Helm values, if the app is a chart
├── kustomization.yaml    # if the app is plain manifests
└── secrets/              # SealedSecrets only; never plaintext
```

Rules that apply to everything in this directory:

- **Pin chart and image versions.** An unpinned chart makes a sync
  non-reproducible, which defeats the point of committing it.
- **Secrets are sealed before they are committed.** A plaintext secret in git
  history is not fixed by deleting the file.
- **Expose internally by default.** Public exposure is an explicit decision per
  app, made through the tunnel, not by opening a port.
