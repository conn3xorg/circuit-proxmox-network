output "bridges" {
  description = "Names of the bridges the circuit manages."
  value       = sort(keys(proxmox_network_linux_bridge.this))
}

output "vnets" {
  description = "IDs of the SDN VNets, which guests use as their bridge, such as net0 = \"bridge=iot\"."
  value       = sort(keys(proxmox_sdn_vnet.this))
}
