# ADR-0005 — OpenTofu for the VM layer, with GitLab-managed remote state

- **Status:** Accepted
- **Decided:** 2026-09-03
- **Recorded:** 2026-09-03
- **Amended:** 2026-09-13 — added the execution host to the decision. The
  original ADR named the tool, the state location and the auth model, but never
  said which machine runs `tofu`.

## Context

The Talos VMs are the one layer between the Proxmox hosts and Kubernetes. Above
them, Argo CD reconciles workloads from Git. Below them, the hosts are installed
by hand from a runbook. The VMs sit in the middle and currently exist nowhere:
not in Git, and not yet on the hypervisor.

That gap decides three things at once, because a tool choice, a state location
and an authentication model cannot be settled independently.

**The layer is small but destructive.** It defines two VMs. A mistaken apply
here does not restart a pod; it deletes a cluster node and its disk. The cluster
has two nodes and no spare capacity to drain to, so a node loss is an outage,
not a rolling update.

**The state file is the single point of failure.** It maps the configuration to
real VM IDs. Lose it and OpenTofu no longer knows the VMs exist: the next apply
proposes to create them again, beside the running ones. This laptop is not a
safe home for that file.

**The code repo is public.** It is the flagship portfolio piece
([R4](../../README.md)), which rules out any pattern that keeps credentials or
state in the tree. A `.gitignore` entry is a weak guard when the cost of a miss
is a leaked hypervisor token.

**The layer runs before its own output exists.** It creates the first VMs, so at
first run there is no VM to run it from. The in-cluster GitLab Runner of
[R17](../../README.md) is made of the nodes this layer creates. An executor
inside the target is therefore circular at bootstrap, whatever its merits later.

## Decision

Define the VM layer in **OpenTofu** with the **`bpg/proxmox`** provider, pinned
to patch releases of `0.111.1`. The configuration lives in `infra/tofu/`.

Keep **state in GitLab-managed Terraform state**, in a **private project that is
separate from this repo**, reached through the `http` backend as a partial
configuration. Local state is never written.

Authenticate to Proxmox as a **dedicated `tofu@pve` user holding a custom
minimal role**, through an API token supplied by the environment. Never as
`root@pam`.

Treat **`tofu plan` as the review artifact and every apply as manual**. No
pipeline applies this layer.

### Where the layer executes

Run `tofu` from a **human-operated workstation**. Today that is the Persephone
desktop. No machine is master of this layer: the state file in GitLab holds the
authority, and the lock serialises whoever runs. Any host with the repo, the two
backend credentials and the PVE token is a valid executor.

Four earlier decisions already make the executor replaceable, and they are the
reason a workstation is safe here:

| Property       | What makes it portable                                                                                                                       |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| State          | Remote in GitLab. The workstation holds no authority. Reinstall it and the layer survives                                                    |
| Provider build | `.terraform.lock.hcl` is tracked. A second host resolves the identical build                                                                 |
| Credentials    | Read from the environment only. Nothing machine-specific is committed                                                                        |
| Backend        | Partial configuration plus `backend.hcl.example`. A new host is one file copy, and a misconfigured one stops rather than writing local state |

A pipeline may later run **`tofu plan` on a merge request**, because a plan is
read-only and makes the review artifact automatic. **Apply stays manual**, per
the decision above. That split is the only CI this layer ever gets.

## Options considered

| Option                                         | Why it was plausible                                                             | Why it lost                                                                                                                                                                                                                                                                          |
| ---------------------------------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Terraform instead of OpenTofu                  | Larger ecosystem, and the name a recruiter recognises                            | The BUSL relicensing is the reason OpenTofu exists. The provider and the HCL are the same, so the skill transfers either way, and the fork is the choice a platform team makes today                                                                                                 |
| `Telmate/proxmox` provider                     | The older and more widely blogged provider                                       | Slower release cadence and thinner Proxmox 8/9 coverage. `bpg/proxmox` is actively maintained and models PVE 9 resources the project needs                                                                                                                                           |
| Ansible for the VM layer                       | Already a candidate for the host layer (`idea.md`), so one tool would cover both | Ansible describes steps, not desired state. It has no state file, so it cannot tell a drifted VM from a correct one, and "a rebuild costs one apply" stops being true                                                                                                                |
| Proxmox VM templates cloned by hand            | No new tool, and fast for two VMs                                                | Leaves the middle layer out of Git, which is the whole gap this closes. Two VMs is exactly the size at which the habit is cheap to build                                                                                                                                             |
| Local state, backed up manually                | Simplest thing that works                                                        | A backup that depends on remembering to take it is not a backup. The failure mode is duplicate VMs, and it appears only when you are already recovering from something else                                                                                                          |
| State in this repo's own GitLab project        | State lives beside the code it describes; one project, one token                 | GitLab authenticates state access regardless of project visibility, so this is not a live exposure. It lost on blast radius: a visibility or token-scope mistake on a public project would then reach state as well as code. A separate project keeps those two mistakes independent |
| S3-compatible state (MinIO in-cluster)         | Provider-neutral, and a normal production pattern                                | Circular. The VM layer would depend on a cluster that the VM layer creates. Revisit only for state that Kubernetes does not host                                                                                                                                                     |
| `root@pam` API token                           | Works with no role modelling                                                     | Full cluster privileges on a token held in a shell environment, on a layer whose whole point is limiting damage. The custom role costs one session and is the part worth showing                                                                                                     |
| A dedicated admin VM on labnet                 | Keeps credentials off the daily driver, and gives one blessed executor           | Circular in the same way as the in-cluster runner. The VM would either manage itself or sit outside the layer that manages everything else. It also costs RAM the two minis do not have: the worker already takes 12 GB of 16                                                        |
| The in-cluster GitLab Runner applies the layer | Matches the GitOps pattern every layer above this one follows                    | Cannot exist at bootstrap, and must not exist after. The runner runs on the nodes this layer deletes and recreates. An unattended apply would remove the node running the apply                                                                                                      |
| `tofu` on a PVE node itself                    | Always reachable, and needs no API token at all                                  | Puts the tool that destroys VMs on the host that serves them. It also breaks the clean-install runbook: the node stops being reproducible from [ADR-0001](0001-proxmox-and-clean-install.md) alone                                                                                   |

## Consequences

A node rebuild becomes `tofu apply` against a reviewed plan, instead of an
evening of wizard screens. VM sizes, disks and VLAN tags become reviewable diffs
and stop living in one person's memory.

The state project is now infrastructure. It joins the backup scope of
[R20](../../README.md), and losing access to GitLab means losing the ability to
change the VM layer until access returns. The hosts and the cluster keep running
without it.

Two things get harder, honestly. `tofu init` now needs
`-backend-config=backend.hcl`, so a fresh clone is two steps rather than one —
the cost of not writing a private project ID into a public repo. And the custom
PVE role must grow whenever a new resource needs a privilege: the first symptom
is a permission error mid-plan, not a clear message. `docs/` records the
privilege list so the next failure is diagnosable.

This layer stays outside CI on purpose, which breaks the pattern every other
layer follows. That is deliberate: `helm template` in a pipeline cannot delete a
node, and an unattended apply here can.

One upstream risk is already visible. `tofu init` warns that the GPG key for
`bpg/proxmox` on the OpenTofu registry **has expired**, and that this will fail
in a future OpenTofu version. The provider installs today, and the signature
still verifies. The key belongs to upstream, so there is nothing to fix here —
only something to recognise. The failure will arrive as an `init` that worked
last week and now refuses, right after an OpenTofu upgrade. Check the provider
release notes before you raise the version pin.

The workstation carries two costs, and both need a habit rather than a control.
**Two long-lived credentials sit in a shell on a daily-driver Windows machine.**
Hold them as session variables, never in the user profile, and keep the token
expiry short. **A workstation invites an apply against uncommitted edits.** The
rule is commit first, then apply. No pipeline enforces it here, so the operator
does. A plan job on a merge request would enforce it, which is the strongest
argument for adding one later.
