# clusters/homelab/

Argo CD applications for the `homelab` cluster, arranged as **app-of-apps**: a
root application watches this directory, and every application it finds here is
itself managed by Argo. Adding a workload is adding a file here, not running a
command.

Consequences worth understanding before editing:

- **Argo manages itself from this directory.** A broken manifest here can leave
  Argo unable to reconcile the thing that would fix it. Validate before merging.
- **Sync order matters for bootstrap dependencies.** Anything the cluster needs
  in order to pull from git — CNI, secrets decryption, DNS — must not depend on
  something Argo has not synced yet. Use sync waves where ordering is real.
- **The DNS bootstrap rule:** cluster components and the nodes themselves use
  upstream DNS, never the in-cluster DNS server. Otherwise a DNS outage becomes
  unrecoverable, because the thing that fixes DNS needs DNS to deploy.
