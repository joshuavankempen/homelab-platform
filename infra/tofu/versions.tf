# Version pins for the VM layer.
#
# The bpg/proxmox provider is pre-1.0. A minor bump can change a resource
# schema, so this pin accepts patch releases only. Raise the minor version
# deliberately: read the provider changelog, run `tofu plan`, and confirm the
# plan is empty before you commit the new pin.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111.1"
    }
  }

  # State lives in GitLab-managed Terraform state, in a private project that is
  # separate from this public repo. The block stays empty on purpose. This is a
  # partial backend configuration:
  #
  #   tofu init -backend-config=backend.hcl
  #
  # `backend.hcl` carries the addresses and is git-ignored, because it names a
  # private project. `backend.hcl.example` documents its shape. The two
  # credentials come from the environment:
  #
  #   TF_HTTP_USERNAME   GitLab username
  #   TF_HTTP_PASSWORD   personal or project access token, scope `api`
  #
  # An empty block also fails closed. Without `-backend-config`, `tofu init`
  # stops and asks for the address. It never falls back to local state.
  backend "http" {}
}
