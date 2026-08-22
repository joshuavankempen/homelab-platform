# clusters/homelab/

This directory holds the Argo CD applications for the `homelab` cluster, in an
**app-of-apps** arrangement. A root application watches this directory. Argo
then manages every application it finds here. A new workload is a new file here,
not a command.

_State: this directory holds no Argo CD application yet. The notes below
describe the target layout — see the [root README](../../README.md)._

Understand these consequences before you edit a file here:

- **Argo manages itself from this directory.** A broken manifest here can stop
  Argo before it reconciles the fix for that manifest. Validate before you
  merge.
- **Sync order matters for a bootstrap dependency.** The cluster needs a CNI,
  secrets decryption and DNS before it can pull from git. Each of those must
  depend only on a component that Argo already synced. Use sync waves where the
  order is real.
- **The DNS bootstrap rule:** cluster components and the nodes use upstream DNS,
  never the in-cluster DNS server. Otherwise a DNS outage becomes unrecoverable,
  because the fix for DNS needs DNS to deploy.
