#!/usr/bin/env bash
# Capture a laptop's hardware profile into hardware/<name>/ for the kernel and firmware steps of the build guide.
# Usage: scripts/capture-hardware.sh <name>     (run on the laptop being profiled)
set -euo pipefail

name=${1:?usage: capture-hardware.sh <name>}
out="$(cd "$(dirname "$0")/.." && pwd)/hardware/$name"
mkdir -p "$out"

lscpu > "$out/lscpu.txt"
free -h > "$out/memory.txt"
lspci -nnk > "$out/lspci.txt"
lsusb > "$out/lsusb.txt"
lsmod > "$out/lsmod.txt"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT > "$out/disks.txt"
cp "/boot/config-$(uname -r)" "$out/kernel.config"

{
  if [ -d /sys/firmware/efi ]; then echo "UEFI"; else echo "BIOS"; fi
  mokutil --sb-state 2>/dev/null || echo "Secure Boot state: unknown (mokutil not installed)"
  if ls /sys/class/tpm/tpm* >/dev/null 2>&1; then echo "TPM: present"; else echo "TPM: not found"; fi
} > "$out/platform.txt"

# Firmware files the kernel loaded this boot (needs read access to the kernel log).
journalctl -k -b --no-pager 2>/dev/null \
  | grep -i firmware \
  | grep -oE '[A-Za-z0-9_./-]+\.(bin|ucode|ri|sfi|fw|pnvm|ddc|sbin)' \
  | sort -u > "$out/firmware.txt" || true

echo "Saved hardware profile to $out"
