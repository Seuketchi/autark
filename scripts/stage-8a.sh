#!/bin/bash
# Phase 8a, part 1 (run as root via pkexec, with Autark mounted at /mnt/lfs by open-autark-rw.sh):
# copy the verified staging folder into Autark's /sources, re-verify every checksum there, then rebuild the kernel
# with the phase 8a options (and a fresh initramfs + signed image), then build phase 8a. Already-done steps are skipped.
set -euo pipefail
LFS=/mnt/lfs
REPO=/home/tan/personal/autark
mountpoint -q $LFS || { echo "$LFS is not mounted"; exit 1; }
[ "$(findmnt -no SOURCE $LFS)" = /dev/mapper/autark ] || { echo "$LFS is not Autark's root"; exit 1; }

echo "== copy sources"
install -m 0644 "$REPO"/sources-8a/* $LFS/sources/
echo "== re-verify inside Autark"
cd $LFS/sources
md5sum --quiet -c "$REPO/sources-8a/md5sums"
sha256sum --quiet -c "$REPO/sources-8a/sha256sums"
echo "   all checksums OK"

echo "== kernel"
LFS=$LFS INSIDE=ch10-kernel-inside.sh bash "$REPO/scripts/lfs/ch7-chroot.sh"
rm -f $LFS/sources/.done/boot-initramfs $LFS/sources/.done/boot-uki
echo "== initramfs + signed image"
LFS=$LFS INSIDE=step6-boot-inside.sh bash "$REPO/scripts/lfs/ch7-chroot.sh"
echo "== stage 1 done"

echo "== phase 8a packages"
LFS=$LFS INSIDE=phase8a-inside.sh bash "$REPO/scripts/lfs/ch7-chroot.sh"
echo "== phase 8a done"
