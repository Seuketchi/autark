#!/bin/bash
# install-test.sh: boot the installer image (make-installer-image.sh) in qemu with UEFI firmware and a blank NVMe disk,
# to try autark-install without touching a real disk (docs/specs/installer.md).
#
#   scripts/qemu-test/install-test.sh INSTALLER.img [--disk DISK.img] [--size 40G] [--boot-disk] [--no-kvm]
#
# First run: creates a blank DISK.img (default install-test-disk.img next to the installer image, sparse) and boots the
# stick; the console is this terminal (serial) and a window. Log in is automatic; run autark-install on /dev/nvme0n1.
# Second run with --boot-disk: boots the disk alone, to see that the installed system comes up and asks for its
# passphrase. The firmware is OVMF without Secure Boot keys, so the unsigned live image boots; the installed system's
# Secure Boot enrolment can't be tested here yet (no OVMF variable store with enrolment, no TPM: swtpm has no recipe).
set -euo pipefail

STICK= DISK= SIZE=40G BOOTDISK=0 KVM=1
die() { echo "install-test: $*" >&2; exit 1; }
usage() { sed -n '2,/^set -e/p' "$0" | sed '$d;s/^# \{0,1\}//' >&2; exit 2; }
[ $# -gt 0 ] || usage
STICK=$1; shift
while [ $# -gt 0 ]; do
  case $1 in
    --disk) DISK=${2:?}; shift ;;
    --size) SIZE=${2:?}; shift ;;
    --boot-disk) BOOTDISK=1 ;;
    --no-kvm) KVM=0 ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
  shift
done
[ -f "$STICK" ] || die "no such image: $STICK"
[ -n "$DISK" ] || DISK=$(dirname "$STICK")/install-test-disk.img
command -v qemu-system-x86_64 > /dev/null || die "qemu-system-x86_64 not found (autark-pkg install qemu)"

CODE= VARS_TEMPLATE=
for d in /usr/share/OVMF /usr/share/edk2/ovmf /usr/share/ovmf /usr/share/edk2-ovmf; do
  for c in OVMF_CODE_4M.fd OVMF_CODE.fd; do [ -f "$d/$c" ] && CODE=$d/$c && break; done
  for v in OVMF_VARS_4M.fd OVMF_VARS.fd; do [ -f "$d/$v" ] && VARS_TEMPLATE=$d/$v && break; done
  [ -z "$CODE" ] || [ -z "$VARS_TEMPLATE" ] || break
done
[ -n "$CODE" ] && [ -n "$VARS_TEMPLATE" ] || die "no OVMF firmware found (autark-pkg install ovmf)"
VARS=${DISK%.img}-vars.fd
[ -f "$VARS" ] || cp "$VARS_TEMPLATE" "$VARS"
[ -f "$DISK" ] || { truncate -s "$SIZE" "$DISK"; echo "made a blank $SIZE disk: $DISK"; }

accel=(); [ "$KVM" = 0 ] || accel=(-enable-kvm -cpu host)
drives=(-drive "file=$DISK,format=raw,if=none,id=target" -device nvme,drive=target,serial=autark-target,bootindex=2)
if [ "$BOOTDISK" = 1 ]; then
  stick=()
else
  stick=(-drive "file=$STICK,format=raw,if=none,id=stick,readonly=on" -device usb-ehci -device usb-storage,drive=stick,bootindex=1)
fi
exec qemu-system-x86_64 "${accel[@]}" -smp 4 -m 4G \
  -drive if=pflash,format=raw,readonly=on,file="$CODE" \
  -drive if=pflash,format=raw,file="$VARS" \
  "${drives[@]}" "${stick[@]}" \
  -nic user,model=virtio-net-pci -display gtk -serial mon:stdio
