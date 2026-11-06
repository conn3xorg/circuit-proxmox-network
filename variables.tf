variable "node_name" {
  type        = string
  description = "The Proxmox VE node the bridges and VLAN interfaces go on, such as \"pve1\". SDN zones are limited to this node too."
}

variable "bridges" {
  type = map(object({
    ports      = optional(list(string), [])
    vlan_aware = optional(bool, true)
    vids       = optional(string, "2-4094")
    address    = optional(string)
    mtu        = optional(number)
    comment    = optional(string)
  }))
  default     = {}
  description = "Linux bridges, by name, such as { vmbr1 = { ports = [\"eno2\"] } }. VLAN-aware by default, carrying VLANs 2 to 4094; vids is a space-separated list of IDs and ranges, such as \"10 20-30\". address is an IPv4 CIDR for the node on the bridge. No gateway: the node's default route stays where it is."

  validation {
    condition     = alltrue([for name in keys(var.bridges) : can(regex("^[A-Za-z][A-Za-z0-9_]{0,9}$", name))])
    error_message = "Bridge names start with a letter and have at most 10 letters, digits and underscores, such as \"vmbr1\"."
  }

  validation {
    condition     = alltrue([for b in var.bridges : b.vlan_aware || b.vids == "2-4094"])
    error_message = "vids only applies to a VLAN-aware bridge."
  }
}

variable "manage_vmbr0" {
  type        = bool
  default     = false
  description = "Allow bridges to include vmbr0. On most nodes it carries the address you reach the node on, and a mistake there cuts you off, so it's refused unless this is true."

  validation {
    condition     = var.manage_vmbr0 || !contains(keys(var.bridges), "vmbr0")
    error_message = "bridges includes vmbr0, which usually carries the node's own address. Set manage_vmbr0 = true if you mean it."
  }
}

variable "vlan_interfaces" {
  type = map(object({
    interface = string
    vlan      = number
    address   = optional(string)
    comment   = optional(string)
  }))
  default     = {}
  description = "VLAN interfaces on the node, by any label, such as { iot = { interface = \"vmbr1\", vlan = 20, address = \"10.20.0.2/24\" } }. Each is named <interface>.<vlan>. Use one to give the node an address on a VLAN that a VLAN-aware bridge carries."

  validation {
    condition     = alltrue([for v in var.vlan_interfaces : v.vlan >= 1 && v.vlan <= 4094 && floor(v.vlan) == v.vlan])
    error_message = "Each vlan must be a whole number from 1 to 4094."
  }
}

variable "sdn_zones" {
  type = map(object({
    type   = optional(string, "simple")
    bridge = optional(string)
    mtu    = optional(number)
  }))
  default     = {}
  description = "SDN zones, by ID, such as { lab = {} }. type is simple (an isolated bridge per VNet, routed by the node) or vlan (VNets are VLANs on bridge, which must be VLAN-aware)."

  validation {
    condition     = alltrue([for id, z in var.sdn_zones : can(regex("^[a-z][a-z0-9]{0,7}$", id))])
    error_message = "SDN zone IDs are 1 to 8 lowercase letters and digits, starting with a letter."
  }

  validation {
    condition     = alltrue([for z in var.sdn_zones : z.type == "simple" && z.bridge == null || z.type == "vlan" && z.bridge != null])
    error_message = "type must be simple, with no bridge, or vlan, with a bridge."
  }
}

variable "vnets" {
  type = map(object({
    zone  = string
    tag   = optional(number)
    alias = optional(string)
    subnets = optional(map(object({
      gateway = optional(string)
      snat    = optional(bool, false)
    })), {})
  }))
  default     = {}
  description = "SDN VNets, by ID, such as { iot = { zone = \"lab\", subnets = { \"10.50.0.0/24\" = { gateway = \"10.50.0.1\" } } } }. tag is the VLAN ID in a vlan zone. Subnets are keyed by CIDR; in a simple zone the node takes the gateway address, and snat lets guests out through the node's own address."

  validation {
    condition     = alltrue([for id, v in var.vnets : can(regex("^[a-z][a-z0-9]{0,7}$", id))])
    error_message = "VNet IDs are 1 to 8 lowercase letters and digits, starting with a letter."
  }

  validation {
    condition     = alltrue([for v in var.vnets : contains(keys(var.sdn_zones), v.zone)])
    error_message = "Each VNet's zone must be one of sdn_zones."
  }

  validation {
    condition     = alltrue([for v in var.vnets : alltrue([for cidr in keys(v.subnets) : can(cidrhost(cidr, 0))])])
    error_message = "Subnet keys must be CIDR blocks, such as \"10.50.0.0/24\"."
  }
}
