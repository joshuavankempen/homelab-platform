#!/usr/bin/env bash
#
# Read-only discovery of the Proxmox cluster, for the OpenTofu VM layer.
#
# The VM resources need facts that no file in this repo records: storage IDs and
# free space, which datastore accepts `iso` content, whether `vmbr0` is
# VLAN-aware, free memory per node, and the VM IDs already in use.
#
# This script only reads. It runs no command that changes cluster state, and it
# needs no DRY_RUN switch. Every command below is a query.
#
# Run it from the workstation. It reaches the nodes over SSH, using the host
# aliases in ~/.ssh/config:
#
#   ./scripts/discover-pve.sh
#   ./scripts/discover-pve.sh > ~/pve-discovery.txt
#
# Override the node list when the cluster grows:
#
#   NODES="pve-lenovo pve-hp pve-new" ./scripts/discover-pve.sh
#
# On Windows, run it from Git Bash but point SSH_BIN at Windows OpenSSH. The two
# implementations use different agent sockets: a key held by the Windows
# ssh-agent service is invisible to the ssh that Git Bash bundles. The symptom
# is `Permission denied (publickey)` on a key that works when you type its
# passphrase by hand. The default below already does this when the file exists.
#
set -euo pipefail

NODES="${NODES:-pve-lenovo pve-hp}"

# SSH client. Windows OpenSSH reads the persistent ssh-agent service, so prefer
# it when it is present. Override explicitly if you keep keys elsewhere.
WINDOWS_SSH="/c/Windows/System32/OpenSSH/ssh.exe"
if [[ -z "${SSH_BIN:-}" ]] && [[ -x "$WINDOWS_SSH" ]]; then
  SSH_BIN="$WINDOWS_SSH"
fi
SSH_BIN="${SSH_BIN:-ssh}"

# The node that answers cluster-wide queries. Any member returns the same data,
# because /etc/pve is a shared filesystem.
PRIMARY="${PRIMARY:-${NODES%% *}}"

# SSH options. BatchMode fails immediately instead of prompting for a password:
# the nodes accept publickey only, so a prompt means the key is wrong.
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10)

log()  { printf '%s [INFO] %s\n'  "$(date +%Y-%m-%dT%H:%M:%S)" "$*" >&2; }
warn() { printf '%s [WARN] %s\n'  "$(date +%Y-%m-%dT%H:%M:%S)" "$*" >&2; }
die()  { printf '%s [ERROR] %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# Print a heading so the report stays readable when redirected to a file.
section() {
  printf '\n\n===============================================================\n'
  printf '== %s\n' "$1"
  printf '===============================================================\n'
}

# Run a read-only command on a node and label it. A failed query is a finding,
# not a fatal error: an absent command still tells you something about the node.
remote() {
  local node="$1" label="$2" cmd="$3"
  printf '\n--- %s ---\n' "$label"
  if ! "$SSH_BIN" "${SSH_OPTS[@]}" "$node" "$cmd" 2>&1; then
    warn "query failed on ${node}: ${label}"
  fi
}

preflight() {
  require_cmd date
  [[ -x "$SSH_BIN" ]] || require_cmd "$SSH_BIN"
  log "using SSH client: ${SSH_BIN}"

  local node
  for node in $NODES; do
    log "preflight: testing SSH to ${node}"
    # Keep the two failure modes apart. BatchMode suppresses both prompts, so
    # both arrive as a refusal rather than a question, and they need opposite
    # fixes. Read the ssh line above this message to tell them apart.
    "$SSH_BIN" "${SSH_OPTS[@]}" "$node" true || die \
      "cannot reach ${node} over SSH. Two causes look alike here.

    'Permission denied (publickey)' — the key is passphrase-protected and
    BatchMode blocks the prompt. Load the key into the Windows ssh-agent.
    In an elevated PowerShell, once per machine:
      Set-Service ssh-agent -StartupType Automatic
      Start-Service ssh-agent
    Then in a normal shell:
      ssh-add \"\$env:USERPROFILE\\.ssh\\homelab_ed25519\"
      ssh-add -l
    Git Bash cannot read that agent, so SSH_BIN must point at Windows
    OpenSSH. It does by default.

    'Host key verification failed' — the host is absent from known_hosts, and
    BatchMode blocks the accept prompt. Do not blind-accept it. Read the
    fingerprint from a node you already trust:
      ssh <trusted-node> 'ssh-keyscan -t ed25519 ${node} | ssh-keygen -lf -'
    Then run 'ssh ${node}' by hand, compare the two fingerprints, and accept
    only if they match."
  done
  log "preflight passed for: ${NODES}"
}

cluster_facts() {
  section "CLUSTER — queried on ${PRIMARY}"

  # Quorum matters for the VM layer. A two-node cluster with no QDevice loses
  # quorum when either node stops, and /etc/pve then goes read-only. An apply
  # fails at exactly that moment. Look for "Expected votes" and any qdevice line.
  remote "$PRIMARY" "pvecm status (quorum, votes, QDevice)" \
    'pvecm status'
  remote "$PRIMARY" "pvecm nodes" \
    'pvecm nodes'
  remote "$PRIMARY" "pveversion" \
    'pveversion -v | head -n 5'

  # Storage. `pvesm status` gives IDs, type, and free space in bytes. The
  # storage.cfg shows which content types each datastore accepts: the Talos ISO
  # needs one that lists `iso`, and the VM disks need one that lists `images`.
  remote "$PRIMARY" "pvesm status (all storage, free space)" \
    'pvesm status'
  remote "$PRIMARY" "pvesm status --content iso (ISO-capable datastores)" \
    'pvesm status --content iso'
  remote "$PRIMARY" "pvesm status --content images (VM-disk-capable datastores)" \
    'pvesm status --content images'
  remote "$PRIMARY" "storage.cfg (content types per datastore)" \
    'cat /etc/pve/storage.cfg'

  # VM IDs already taken, cluster-wide. /cluster/resources covers both nodes,
  # which `qm list` does not. nextid is the first free ID the cluster suggests.
  remote "$PRIMARY" "VM and container IDs in use (cluster-wide)" \
    'pvesh get /cluster/resources --type vm --output-format json 2>/dev/null || pvesh get /cluster/resources --type vm'
  remote "$PRIMARY" "next free VMID" \
    'pvesh get /cluster/nextid'
}

node_facts() {
  local node
  for node in $NODES; do
    section "NODE — ${node}"

    # Memory decides whether the planned VM fits. `free -m` reports the live
    # figure; the total is what the VM sizing must respect.
    remote "$node" "memory (MB)" \
      'free -m'
    remote "$node" "CPU count" \
      'nproc'

    # VLAN awareness on the bridge. A VLAN tag on a VM NIC only works when the
    # bridge carries `bridge-vlan-aware yes`. Without it, the tag is silently
    # ignored and the VM lands on the untagged network.
    remote "$node" "network interfaces (look for bridge-vlan-aware)" \
      'cat /etc/network/interfaces'
    remote "$node" "bridge VLAN filtering state" \
      'cat /sys/class/net/vmbr0/bridge/vlan_filtering 2>/dev/null || echo "vmbr0 absent or not a bridge"'
    remote "$node" "link summary" \
      'ip -brief link show'

    # Local guests on this node, with their configured memory.
    remote "$node" "VMs on this node" \
      'qm list'
    remote "$node" "containers on this node" \
      'pct list'
  done
}

main() {
  preflight
  printf 'Proxmox discovery report\n'
  printf 'Generated: %s\n' "$(date -Iseconds)"
  printf 'Nodes: %s\n' "$NODES"
  cluster_facts
  node_facts
  printf '\n'
  log "discovery complete"
}

main "$@"
