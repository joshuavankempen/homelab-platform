# infra/tofu/

This directory holds the OpenTofu definitions for the VM layer. They define the
Talos virtual machines on Proxmox: sizes, disks, VLAN tags, and boot media. They
use the `bpg/proxmox` provider.

_State: both Talos VMs and their boot ISOs are applied from GitLab-managed
state. The ISO is Talos v1.14.1, and both nodes run Talos installed to disk —
see the [root README](../../README.md)._

This is the layer that makes a node rebuild a command rather than an evening.

Notes:

- **The state is remote, not local.** Local state on a laptop is a single point
  of failure for the whole estate. `.gitignore` excludes `*.tfstate`
  deliberately.
- **`tofu plan` is the review artifact.** An apply is deliberate and manual. No
  automation reconciles a VM change, because a mistaken apply here destroys a
  node rather than restarts a pod.
- **Credentials come from the environment**, never from a committed `.tfvars`
  file. `*.tfvars.example` documents the shape without the values.

## First run

```sh
tofu init -backend-config=backend.hcl
```

Copy `backend.hcl.example` to `backend.hcl` first, and fill in the project ID.
`backend.hcl` stays git-ignored, because it names a private project and this
repo is public. The backend block is a partial configuration, so `tofu init`
without `-backend-config` stops and asks. It never falls back to local state.

Set both state credentials in the shell before the first `init`. See
`versions.tf` for the token shape.

## Raise the Talos version

Keep `talos_version` equal to `talosVersion` in
[`infra/talos/talconfig.yaml`](../talos/talconfig.yaml). A maintenance-mode
node validates the machine config with the ISO system, and an older ISO can
reject newer document kinds.

1. Change `talos_version` and `talos_iso_checksum` in one commit. Take the
   checksum of `metal-amd64.iso` from the release `sha256sum.txt`.
2. Run `tofu plan`. Expect the ISO downloads as `+/-` (create before destroy)
   and the VMs as `~` in-place, with only `cdrom.file_id` and `description`
   changed.
3. Run `tofu apply`. **The old ISO delete fails with a 403 on
   `Datastore.Allocate`, and that is expected.** The role lacks that privilege
   on purpose — see
   [ADR-0005](../../docs/adr/0005-opentofu-vm-layer-and-remote-state.md). The
   new ISO and the cdrom change are already in place when the error appears.
4. Delete the old ISO from `local` on each node, as root in the PVE UI.
5. Run `tofu plan` again. The refresh finds the files missing and drops the
   deposed objects. Apply that plan, and expect `0 destroyed`.

A running VM keeps the old system in RAM after the cdrom change. A node in
maintenance mode needs a reset to boot the new ISO. `qm reset` does not reset
the Proxmox uptime counter, so confirm the reboot with the Talos version, not
the uptime.

## On Windows PowerShell

Two quoting rules, and both produce errors that point somewhere else.

**Quote every value in an assignment.** PowerShell runs a bare unquoted word as
a command, so `$env:TF_HTTP_USERNAME = myname` reports `The term 'myname' is not
recognized`. Use single quotes, not double: a token that contains `$` is
silently truncated by double quotes, and the result reads as a 401.

```powershell
$env:TF_HTTP_USERNAME = 'your-gitlab-username'
$env:TF_HTTP_PASSWORD = 'glpat-...'
```

**Quote the whole backend argument.** PowerShell splits
`-backend-config=backend.hcl` at the `=`, and `tofu` then reports
`Too many command line arguments`, which sounds like a syntax error in the
command rather than in the shell.

```powershell
tofu init "-backend-config=backend.hcl"
```

Neither rule applies on Linux. They apply here because
[ADR-0005](../../docs/adr/0005-opentofu-vm-layer-and-remote-state.md) puts the
executor on a human-operated workstation, and that workstation runs Windows.
