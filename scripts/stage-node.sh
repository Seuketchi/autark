#!/bin/bash
# Node.js, curl and git phase (run as root via pkexec, with Autark mounted at /mnt/lfs by open-autark-rw.sh):
# copy the verified sources-node folder into Autark's /sources, re-verify every checksum there, then build.
# No kernel or boot steps. Already-built packages are skipped.
set -euo pipefail
LFS=/mnt/lfs
REPO=/home/tan/personal/autark
mountpoint -q $LFS || { echo "$LFS is not mounted"; exit 1; }
[ "$(findmnt -no SOURCE $LFS)" = /dev/mapper/autark ] || { echo "$LFS is not Autark's root"; exit 1; }

echo "== copy sources"
install -m 0644 "$REPO"/sources-node/*.tar.* $LFS/sources/
echo "== re-verify inside Autark"
cd $LFS/sources
md5sum --quiet -c "$REPO/sources-node/md5sums"
sha256sum --quiet -c "$REPO/sources-node/sha256sums"
echo "   all checksums OK"

echo "== node, curl, git"
LFS=$LFS INSIDE=phase-node-inside.sh bash "$REPO/scripts/lfs/ch7-chroot.sh"
echo "== node phase done"
