#!/bin/bash
# Copies a hardware profile's kernel inputs into $LFS/sources, where ch10-kernel-inside.sh reads them.
#
#   LFS=/mnt/lfs scripts/lfs/stage-profile.sh <profile> [--generic] [--luks-uuid <uuid>]
#
# <profile> is a folder in hardware/ (see hardware/README.md). With its lsmod.txt the kernel is trimmed to the modules
# that machine loads; --generic leaves out lsmod.txt, firmware.list and the profile's CPU microcode file, so the
# kernel keeps every module and the boot step installs all firmware and microcode: it boots on hardware the profile
# never saw. --luks-uuid (or ROOT_LUKS_UUID in the environment) is the UUID of the encrypted root, which the boot step
# needs.
set -euo pipefail

LFS=${LFS:?set LFS=/mnt/lfs}
usage="usage: stage-profile.sh <profile> [--generic] [--luks-uuid <uuid>]"
profile=${1:?$usage}; shift
generic=0; uuid=${ROOT_LUKS_UUID:-}
while [ $# -gt 0 ]; do
  case $1 in
    --generic) generic=1 ;;
    --luks-uuid) uuid=${2:?$usage}; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
if [ -n "$uuid" ] && ! [[ $uuid =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  echo "not a UUID: $uuid" >&2; exit 2
fi

dir="$(cd "$(dirname "$0")/../.." && pwd)/hardware/$profile"
[ -f "$dir/kernel.config" ] || { echo "no $dir/kernel.config; capture one with scripts/capture-hardware.sh $profile" >&2; exit 1; }
out=$LFS/sources
install -d "$out"

# stage FILE NAME: copy it, or remove a copy left by an earlier profile. Generic leaves the machine's files out.
stage() {
  if [ -f "$dir/$1" ] && [ "$generic" = 0 ]; then install -m 0644 "$dir/$1" "$out/$2"; else rm -f "$out/$2"; fi
}
install -m 0644 "$dir/kernel.config" "$out/target-kernel.config"
stage lsmod.txt target-lsmod.txt
stage kernel.fragment profile-kernel.fragment
stage firmware.list profile-firmware.list

{
  if [ -f "$dir/boot.env" ] && [ "$generic" = 0 ]; then cat "$dir/boot.env"; fi
  if [ -n "$uuid" ]; then echo "ROOT_LUKS_UUID=$uuid"; fi
} > "$out/profile-boot.env"
chmod 0644 "$out/profile-boot.env"

echo "staged $profile for the kernel and boot steps ($([ -e "$out/target-lsmod.txt" ] && echo "trimmed to the profile" || echo generic))"
[ -n "$uuid" ] || echo "note: no --luks-uuid given; the boot step will refuse to run without ROOT_LUKS_UUID"
