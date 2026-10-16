#!/bin/bash
# Build guide Step 7a: boot autark.img in qemu with UEFI firmware (OVMF), on an emulated NVMe disk like the
# laptop's. The serial console (where the disk passphrase prompt appears) is this terminal; a GTK window shows
# the screen. The session is recorded to qemu-boot.log (typed passphrases aren't echoed, so they aren't in it).
# The image must NOT be mounted or attached on the host while this runs.
set -euo pipefail
cd "$(dirname "$0")/.."

if losetup -a | grep -q autark.img || [ -e /dev/mapper/autark ]; then
  echo "autark.img is still attached or unlocked on the host; release it first (build guide 7a step 1)." >&2
  exit 1
fi
[ -f ovmf-vars.fd ] || cp /usr/share/OVMF/OVMF_VARS_4M.fd ovmf-vars.fd

exec script -q -f qemu-boot.log -c "qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 4G \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,file=$PWD/ovmf-vars.fd \
  -drive file=$PWD/autark.img,format=raw,if=none,id=disk \
  -device nvme,drive=disk,serial=autark \
  -display gtk -serial mon:stdio"
