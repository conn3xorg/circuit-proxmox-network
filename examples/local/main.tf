terraform {
  required_providers {
    # The version comes from the circuit's own pin.
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

# up.sh writes lab.auto.tfvars with these.
variable "spare_nic" {
  type = string
}

variable "endpoint" {
  type = string
}

variable "api_token" {
  type      = string
  ephemeral = true
  sensitive = true
}

provider "proxmox" {
  endpoint  = var.endpoint
  api_token = var.api_token
  # The lab node serves its API with a self-signed certificate.
  insecure = true
}

module "network" {
  source = "../.."

  node_name = "pve1"

  # A VLAN-aware bridge on the VM's second NIC, so its own uplink is never
  # touched. On a real node, that's a spare NIC or a bond to a switch trunk.
  bridges = {
    vmbr10 = { ports = [var.spare_nic], comment = "Lab VLANs" }
  }

  # The node's own address on VLAN 20 of that bridge.
  vlan_interfaces = {
    iot = { interface = "vmbr10", vlan = 20, address = "10.20.0.1/24" }
  }

  sdn_zones = {
    routed = {}
    tagged = { type = "vlan", bridge = "vmbr10" }
  }

  vnets = {
    lab50 = { zone = "routed", subnets = { "10.50.0.0/24" = { gateway = "10.50.0.1" } } }
    guest = { zone = "tagged", tag = 30, alias = "Guest Wi-Fi" }
  }
}

output "vnets" {
  value = module.network.vnets
}
