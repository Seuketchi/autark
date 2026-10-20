#!/bin/bash
# install-test.sh: boot the installer image (make-installer-image.sh) in qemu with UEFI firmware and a blank NVMe disk,
# to try autark-install without touching a real disk (docs/specs/installer.md).
#
#   scripts/qemu-test/install-test.sh INSTALLER.img [--disk DISK.img] [--size 40G] [--boot-disk] [--no-kvm] [--display gtk|none]
#
# First run: creates a blank DISK.img (default install-test-disk.img next to the installer image, sparse) and boots the
# stick; the console is this terminal (serial; Ctrl-a x quits), plus a window if this qemu has one. Log in is automatic; run
# autark-install on /dev/nvme0n1. The installed system has no serial console, so --boot-disk needs a window (--display gtk).
# Second run with --boot-disk: boots the disk alone, to see that the installed system comes up and asks for its
# passphrase. The firmware is OVMF without Secure Boot keys, so the unsigned live image boots; the installed system's
# Secure Boot enrolment can't be tested here yet (no OVMF variable store with enrolment, no TPM: swtpm has no recipe).
set -euo pipefail

STICK= DISK= SIZE=40G BOOTDISK=0 KVM=1 DISPLAY_=
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
    --display) DISPLAY_=${2:?}; shift ;;
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
# qemu's own package ships an edk2 build too (the x86_64 variable store is the i386 file).
if [ -z "$CODE" ] || [ -z "$VARS_TEMPLATE" ]; then
  q=/usr/share/qemu
  if [ -f $q/edk2-x86_64-code.fd ] && [ -f $q/edk2-i386-vars.fd ]; then CODE=$q/edk2-x86_64-code.fd VARS_TEMPLATE=$q/edk2-i386-vars.fd; fi
fi
[ -n "$CODE" ] && [ -n "$VARS_TEMPLATE" ] || die "no UEFI firmware found (qemu's edk2 files, or autark-pkg install ovmf)"
VARS=${DISK%.img}-vars.fd
[ -f "$VARS" ] || cp "$VARS_TEMPLATE" "$VARS"
[ -f "$DISK" ] || { truncate -s "$SIZE" "$DISK"; echo "made a blank $SIZE disk: $DISK"; }

# A window if this qemu has one; otherwise the terminal only (the live image and the installed system both log to the
# serial console, ttyS0). Leave qemu with Ctrl-a x.
if [ -z "$DISPLAY_" ]; then
  if qemu-system-x86_64 -display help 2> /dev/null | grep -qx gtk; then DISPLAY_=gtk; else DISPLAY_=none; fi
fi
# The installer needs no network, so a qemu built without user-mode networking (slirp) still works.
nic=(-nic none); if qemu-system-x86_64 -netdev help 2> /dev/null | grep -qx user; then nic=(-nic user,model=virtio-net-pci); fi
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
  "${nic[@]}" -display "$DISPLAY_" -serial mon:stdio
