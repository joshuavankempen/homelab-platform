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
  #   TF_HTTP_PASSWORD   personal access token with granular permissions
  #
  # The token is scoped to the state project alone, and carries exactly three
  # permissions under CI/CD -> Terraform State: Create, Read, Lock. `Create` is
  # the write permission, because a state write is POST .../state/:name and no
  # Update action exists. Leave Delete off.
  #
  # It is a personal access token, not a project access token: project token
  # creation is disabled in the group, and the setting that enables it is absent
  # on this tier. So TF_HTTP_USERNAME is the GitLab username. Were this a project
  # access token, the username would be the token's own name instead.
  #
  # An empty block also fails closed. Without `-backend-config`, `tofu init`
  # stops and asks for the address. It never falls back to local state.
  backend "http" {}
}
