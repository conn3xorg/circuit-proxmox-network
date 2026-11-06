# Local example

Applies circuit-proxmox-network to a throwaway Proxmox VE node on your machine: a Debian 13 VM that `up.sh` turns into a node with [circuit-proxmox](https://github.com/conn3xorg/circuit-proxmox). You need an x86_64 Linux machine with Conn3x, QEMU with KVM (`qemu-system-x86` and `qemu-utils` on Debian and Ubuntu), `cloud-localds` from `cloud-image-utils`, and read and write access to `/dev/kvm`.

```sh
./up.sh
conn3x init
conn3x apply
conn3x plan
./check.sh
```

`up.sh` takes about eight minutes, most of it installing Proxmox VE. The second plan says `No changes.`, and `check.sh` ends with `All checks passed.` It plugs network namespaces into the bridge and the VNets on the node, the way a guest's NIC is plugged in, and sends pings across them.

What `up.sh` does, in order: downloads one dated Debian 13 cloud image once, checks it against the SHA-512 written in the script and keeps it in `~/.cache/circuit-proxmox-network`; boots a fresh copy-on-write disk over it with 2 CPUs and 4 GB of memory, SSH on `127.0.0.1:2222` and the API on `127.0.0.1:8006`; applies circuit-proxmox v0.1.1 from [node](node) to it; adds `source /etc/network/interfaces.d/*` to `/etc/network/interfaces` and starts the node's `networking` service, both of which a node installed from the ISO already has; and makes an API token, written with the API address to `lab.auto.tfvars`, which Conn3x reads by itself. Set `PORT` and `WEB_PORT` to move the two ports, and `CPUS` and `MEMORY` (in MB) to size the VM.

The VM has a second NIC that goes nowhere, and the example's bridge sits on that one, so the VM's own network is never touched. A bridge needs a port here: with none, it has no MAC address, and Proxmox's network reload fails on its VLAN interface.

`./down.sh` stops the VM and removes its disk, the key, the token and both states. The cached image stays for the next run.
