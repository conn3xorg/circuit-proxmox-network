locals {
  subnets = merge([for id, v in var.vnets : { for cidr, s in v.subnets : "${id}/${cidr}" => merge(s, { vnet = id, cidr = cidr }) }]...)
  sdn     = length(var.sdn_zones) > 0
}

# Each bridge and VLAN interface reloads the node's network when it changes,
# the provider's default, so a change takes effect in the same apply.
resource "proxmox_network_linux_bridge" "this" {
  for_each   = var.bridges
  node_name  = var.node_name
  name       = each.key
  ports      = each.value.ports
  vlan_aware = each.value.vlan_aware
  vids       = each.value.vlan_aware ? each.value.vids : null
  address    = each.value.address
  mtu        = each.value.mtu
  comment    = each.value.comment
}

resource "proxmox_network_linux_vlan" "this" {
  for_each  = var.vlan_interfaces
  node_name = var.node_name
  name      = "${each.value.interface}.${each.value.vlan}"
  address   = each.value.address
  comment   = each.value.comment
  # The interface may be a bridge made above.
  depends_on = [proxmox_network_linux_bridge.this]
}

# SDN changes only take effect when they're applied cluster-wide. This one
# is made first and removed last, so a destroy applies the removals too.
resource "proxmox_sdn_applier" "finalizer" {
  count     = local.sdn ? 1 : 0
  on_create = false
}

resource "proxmox_sdn_zone_simple" "this" {
  for_each   = { for id, z in var.sdn_zones : id => z if z.type == "simple" }
  id         = each.key
  nodes      = [var.node_name]
  mtu        = each.value.mtu
  depends_on = [proxmox_sdn_applier.finalizer]
}

resource "proxmox_sdn_zone_vlan" "this" {
  for_each   = { for id, z in var.sdn_zones : id => z if z.type == "vlan" }
  id         = each.key
  nodes      = [var.node_name]
  bridge     = each.value.bridge
  mtu        = each.value.mtu
  depends_on = [proxmox_sdn_applier.finalizer, proxmox_network_linux_bridge.this]
}

resource "proxmox_sdn_vnet" "this" {
  for_each   = var.vnets
  id         = each.key
  zone       = each.value.zone
  tag        = each.value.tag
  alias      = each.value.alias
  depends_on = [proxmox_sdn_zone_simple.this, proxmox_sdn_zone_vlan.this]
}

resource "proxmox_sdn_subnet" "this" {
  for_each = local.subnets
  vnet     = proxmox_sdn_vnet.this[each.value.vnet].id
  cidr     = each.value.cidr
  gateway  = each.value.gateway
  snat     = each.value.snat
}

# Applies SDN after anything above changes, drift put back included.
resource "proxmox_sdn_applier" "apply" {
  count      = local.sdn ? 1 : 0
  on_destroy = false

  lifecycle {
    replace_triggered_by = [
      proxmox_sdn_zone_simple.this,
      proxmox_sdn_zone_vlan.this,
      proxmox_sdn_vnet.this,
      proxmox_sdn_subnet.this,
    ]
  }

  depends_on = [proxmox_sdn_zone_simple.this, proxmox_sdn_zone_vlan.this, proxmox_sdn_vnet.this, proxmox_sdn_subnet.this]
}
