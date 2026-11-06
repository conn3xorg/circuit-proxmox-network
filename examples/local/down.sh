#!/usr/bin/env sh
# Stops the VM and removes everything up.sh and Conn3x created here. The
# downloaded image stays in the cache for the next run.
set -eu
cd "$(dirname "$0")"
if [ -f vm.pid ]; then kill "$(cat vm.pid)" 2>/dev/null || true; fi
rm -rf vm.pid disk.qcow2 seed.img network-config user-data serial.log id_ed25519 id_ed25519.pub known_hosts lab.auto.tfvars \
  .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup \
  node/.terraform node/.terraform.lock.hcl node/terraform.tfstate node/terraform.tfstate.backup
echo "Removed."
