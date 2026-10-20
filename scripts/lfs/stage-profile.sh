#!/bin/bash
# Copies a hardware profile's kernel inputs into $LFS/sources, where ch10-kernel-inside.sh reads them.
#
#   LFS=/mnt/lfs scripts/lfs/stage-profile.sh <profile> [--generic]
#
# <profile> is a folder in hardware/ (see hardware/README.md). With its lsmod.txt the kernel is trimmed to the modules
# that machine loads; --generic leaves lsmod.txt out, so every module of the starting config is built and the
# kernel boots on hardware the profile never saw.
set -euo pipefail

LFS=${LFS:?set LFS=/mnt/lfs}
profile=${1:?usage: stage-profile.sh <profile> [--generic]}
generic=${2:-}
[ -z "$generic" ] || [ "$generic" = --generic ] || { echo "unknown option: $generic" >&2; exit 2; }

dir="$(cd "$(dirname "$0")/../.." && pwd)/hardware/$profile"
[ -f "$dir/kernel.config" ] || { echo "no $dir/kernel.config; capture one with scripts/capture-hardware.sh $profile" >&2; exit 1; }
out=$LFS/sources
install -d "$out"

install -m 0644 "$dir/kernel.config" "$out/target-kernel.config"

if [ -f "$dir/lsmod.txt" ] && [ "$generic" != --generic ]; then
  install -m 0644 "$dir/lsmod.txt" "$out/target-lsmod.txt"
  mode="trimmed to the modules in $profile/lsmod.txt"
else
  rm -f "$out/target-lsmod.txt"
  mode="generic (every module of the starting config)"
fi

if [ -f "$dir/kernel.fragment" ]; then
  install -m 0644 "$dir/kernel.fragment" "$out/profile-kernel.fragment"
else
  rm -f "$out/profile-kernel.fragment"
fi

echo "staged $profile for the kernel build: $mode"
