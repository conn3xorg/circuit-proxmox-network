terraform {
  required_providers {
    # Pinned exactly: a new provider release is a reviewed change to this
    # circuit, tested against a Proxmox VE node before it's tagged.
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.120.0"
    }
  }
}
