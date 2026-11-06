# Turns the lab VM into a Proxmox VE node with circuit-proxmox, so the
# network circuit has something to configure. up.sh runs this.
variable "port" {
  type    = number
  default = 2222
}

module "proxmox" {
  source = "github.com/conn3xorg/circuit-proxmox?ref=v0.1.1"

  hosts                = { pve1 = { address = "127.0.0.1", port = var.port } }
  ssh_private_key_file = "../id_ed25519"
  ssh_known_hosts_file = "../known_hosts"
}
