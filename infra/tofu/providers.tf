# Proxmox API connection.
#
# The endpoint and the API token come from the environment. The provider reads
# both variables itself, so this file never names them:
#
#   PROXMOX_VE_ENDPOINT    https://10.10.60.11:8006/
#   PROXMOX_VE_API_TOKEN   tofu@pve!<token-id>=<uuid>
#
# The token belongs to the dedicated `tofu@pve` user, which holds a custom
# minimal role. It is not a root token. See docs/adr/0005 for the privilege
# list and the reason.
#
# This file sets only the behaviour that the environment cannot express.
#
# No `ssh` block yet. The provider needs SSH for node-level file operations,
# which this layer does not perform: it creates VMs and downloads boot media,
# and both run over the API. Add the block when a resource needs it, not
# before.

provider "proxmox" {
  insecure = var.proxmox_insecure_tls
}
