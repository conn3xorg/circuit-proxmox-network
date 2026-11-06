#!/usr/bin/env bash
# Sends traffic through what the circuit built on the lab node: from network
# namespaces standing in for guests, plugged into the bridge and the VNets
# the way a guest's NIC is. Runs over SSH as root, and removes the
# namespaces when it's done.
set -euo pipefail
cd "$(dirname "$0")"
ssh -q -o BatchMode=yes -o UserKnownHostsFile=known_hosts -i id_ed25519 -p "${PORT:-2222}" root@127.0.0.1 bash -s <<'SH'
set -euo pipefail
pveversion
# plug NAME BRIDGE VLAN ADDRESS: a namespace with a veth on BRIDGE, untagged
# on VLAN when it's set, as Proxmox does for a guest NIC with tag=VLAN.
plug() {
  ip netns add "$1"
  ip link add "v$1" type veth peer name eth0 netns "$1"
  ip link set "v$1" master "$2" up
  if [ -n "$3" ]; then
    bridge vlan del dev "v$1" vid 1
    bridge vlan add dev "v$1" vid "$3" pvid untagged
  fi
  ip -n "$1" addr add "$4" dev eth0
  ip -n "$1" link set eth0 up
}
cleanup() { for ns in c3a c3b c3c c3d; do ip netns del "$ns" 2>/dev/null || true; ip link del "v$ns" 2>/dev/null || true; done; }
trap cleanup EXIT
cleanup
# Proxmox applies SDN in a background task, so the VNets' bridges can take a
# few seconds to appear after the apply returns.
for i in $(seq 30); do
  ip link show guest >/dev/null 2>&1 && ip link show lab50 >/dev/null 2>&1 && break
  [ "$i" -lt 30 ] || { echo "The VNets' bridges never appeared." >&2; exit 1; }
  sleep 1
done

echo "A guest on VLAN 20 of vmbr10 reaches the node's VLAN 20 address"
plug c3a vmbr10 20 10.20.0.2/24
ip netns exec c3a ping -c 3 -W 2 10.20.0.1 >/dev/null

echo "A guest on VLAN 30 of vmbr10 can't, since VLAN 20 is a different network"
plug c3b vmbr10 30 10.20.0.3/24
if ip netns exec c3b ping -c 2 -W 1 10.20.0.1 >/dev/null 2>&1; then echo "VLAN 30 reached VLAN 20." >&2; exit 1; fi

echo "A guest on the guest VNet reaches the one on VLAN 30 of vmbr10, which the vlan zone maps it to"
ip netns exec c3b ip addr flush dev eth0
ip -n c3b addr add 10.30.0.3/24 dev eth0
plug c3c guest "" 10.30.0.2/24
ip netns exec c3c ping -c 3 -W 2 10.30.0.3 >/dev/null

echo "A guest on the lab50 VNet reaches its gateway on the node"
plug c3d lab50 "" 10.50.0.2/24
ip netns exec c3d ping -c 3 -W 2 10.50.0.1 >/dev/null
echo "All checks passed."
SH
