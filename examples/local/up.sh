#!/usr/bin/env sh
# Starts a throwaway Debian 13 VM, turns it into a Proxmox VE node named
# pve1 with circuit-proxmox (node/), and writes lab.auto.tfvars with an API
# token made on it. The VM has a second, empty NIC for the example's bridge.
# SSH is on 127.0.0.1:$PORT (default 2222) with a fresh key
# and its host key in ./known_hosts, and the API on 127.0.0.1:$WEB_PORT
# (default 8006). Needs Conn3x, QEMU with KVM, and cloud-localds from
# cloud-image-utils. Takes about eight minutes, most of it the install.
set -eu
cd "$(dirname "$0")"
port=${PORT:-2222}
web_port=${WEB_PORT:-8006}
# One dated Debian build, checked against its SHA-512 from Debian's
# SHA512SUMS, kept here so moving to a newer build is a reviewed change.
build=20261026-2643
url=https://cloud.debian.org/images/cloud/trixie/$build
image=debian-13-genericcloud-amd64-$build.qcow2
sha512=3ace18e33bdd036edb49d1f79342bd01d2ab980e35194edb0b410435cd543538d286a0bd13bbb0835f7862306e3d385ce2f6a70d8ecf0bd961111166adbc1b8e
cache=${XDG_CACHE_HOME:-$HOME/.cache}/circuit-proxmox-network
mkdir -p "$cache"

if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
  echo "No access to /dev/kvm. Add yourself to the kvm group, or run this where KVM is available." >&2
  exit 1
fi

if ! (cd "$cache" && echo "$sha512  $image" | sha512sum -c --status - 2>/dev/null); then
  curl -fsSL -o "$cache/$image" "$url/$image"
  (cd "$cache" && echo "$sha512  $image" | sha512sum -c --quiet -) || { rm -f "$cache/$image"; exit 1; }
fi

[ -f id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -C circuit-proxmox-network -f id_ed25519
if [ -f vm.pid ]; then kill "$(cat vm.pid)" 2>/dev/null || true; fi
rm -f disk.qcow2 seed.img network-config vm.pid node/terraform.tfstate node/terraform.tfstate.backup
# A copy-on-write disk over the image, so each run starts fresh.
qemu-img create -q -f qcow2 -b "$cache/$image" -F qcow2 disk.qcow2 20G
cat > user-data <<UD
#cloud-config
hostname: pve1
disable_root: false
ssh_pwauth: false
users:
  - name: root
    ssh_authorized_keys: ["$(cat id_ed25519.pub)"]
UD
# DHCP on the first NIC only. The second is the spare the example bridges:
# its far end is a UDP socket nothing listens on, so it's up but empty.
cat > network-config <<NC
version: 2
ethernets:
  uplink:
    match: { macaddress: "52:54:00:12:34:56" }
    dhcp4: true
NC
cloud-localds -N network-config seed.img user-data
# Proxmox asks for at least 2 GB of memory. It was tested with 4.
qemu-system-x86_64 -enable-kvm -cpu host -m "${MEMORY:-4096}" -smp "${CPUS:-2}" \
  -drive file=disk.qcow2,if=virtio -drive file=seed.img,if=virtio,format=raw \
  -nic "user,model=virtio-net-pci,mac=52:54:00:12:34:56,hostfwd=tcp:127.0.0.1:$port-:22,hostfwd=tcp:127.0.0.1:$web_port-:8006" \
  -device virtio-net-pci,netdev=spare,mac=52:54:00:12:34:57 -netdev "socket,id=spare,udp=127.0.0.1:$((port + 20000)),localaddr=127.0.0.1:$((port + 30000))" \
  -display none -serial file:serial.log -daemonize -pidfile vm.pid

ready=
for _ in $(seq 1 90); do
  if ssh-keyscan -T 2 -p "$port" 127.0.0.1 > known_hosts 2>/dev/null && [ -s known_hosts ] &&
    ssh -q -o BatchMode=yes -o UserKnownHostsFile=known_hosts -i id_ed25519 -p "$port" root@127.0.0.1 'cloud-init status --wait >/dev/null 2>&1; true'; then
    ready=1
    break
  fi
  sleep 2
done
[ -n "$ready" ] || { echo "The VM started, but SSH didn't answer on 127.0.0.1:$port. Its console is in serial.log." >&2; exit 1; }

(cd node && conn3x init -input=false >/dev/null && conn3x apply -auto-approve -input=false -var "port=$port")

# Two things a node installed from the ISO already has. SDN writes its
# interfaces to /etc/network/interfaces.d/sdn, which only takes effect if
# /etc/network/interfaces sources that directory; the cloud image's doesn't.
# Proxmox edits a pending interfaces.new when there is one and moves it over
# the file on the next reload, so the line goes in both.
# And ifupdown2 comes in with proxmox-ve after the install's only reboot, so
# its networking service, which Proxmox reloads the network through, hasn't
# run yet.
ssh -q -o UserKnownHostsFile=known_hosts -i id_ed25519 -p "$port" root@127.0.0.1 \
  "for f in /etc/network/interfaces /etc/network/interfaces.new; do
     [ -f \$f ] || continue
     grep -qx 'source /etc/network/interfaces.d/\*' \$f || printf '\nsource /etc/network/interfaces.d/*\n' >> \$f
   done
   grep -qx 'source /etc/network/interfaces.d/\*' /etc/network/interfaces && systemctl start networking"

# privsep 0: the token has root@pam's rights, which a throwaway node is fine with.
token=$(ssh -q -o UserKnownHostsFile=known_hosts -i id_ed25519 -p "$port" root@127.0.0.1 \
  "pveum user token delete root@pam lab >/dev/null 2>&1; pveum user token add root@pam lab --privsep 0 --output-format json" | sed -n 's/.*"value" *: *"\([^"]*\)".*/\1/p')
[ -n "$token" ] || { echo "Couldn't make an API token on the node." >&2; exit 1; }
spare=$(ssh -q -o UserKnownHostsFile=known_hosts -i id_ed25519 -p "$port" root@127.0.0.1 \
  "ip -o link | grep -i 52:54:00:12:34:57 | cut -d: -f2 | tr -d ' '")
[ -n "$spare" ] || { echo "The VM's second NIC is missing." >&2; exit 1; }
umask 077
cat > lab.auto.tfvars <<VARS
spare_nic = "$spare"
endpoint  = "https://127.0.0.1:$web_port/"
api_token = "root@pam!lab=$token"
VARS
echo "Ready: Proxmox VE node pve1 at https://127.0.0.1:$web_port. Now run: conn3x init && conn3x apply"
