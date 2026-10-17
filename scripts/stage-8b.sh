#!/bin/bash
# Phase 8b (run as root via pkexec, with Autark mounted at /mnt/lfs by open-autark-rw.sh), after scripts/fetch-8b.sh:
# copy sources-8b into Autark's /sources, re-verify every checksum there, then build phase 8b. No kernel or boot
# steps. Already-built packages are skipped; names after the script build only those (see phase8b-inside.sh).
set -euo pipefail
LFS=/mnt/lfs
REPO=$(cd "$(dirname "$0")/.." && pwd)
mountpoint -q $LFS || { echo "$LFS is not mounted"; exit 1; }
[ "$(findmnt -no SOURCE $LFS)" = /dev/mapper/autark ] || { echo "$LFS is not Autark's root"; exit 1; }
[ -e "$REPO/sources-8b/sha256sums" ] || { echo "run scripts/fetch-8b.sh first"; exit 1; }

echo "== copy sources"
install -m 0644 "$REPO"/sources-8b/*.tar* $LFS/sources/
echo "== re-verify inside Autark"
cd $LFS/sources
md5sum --quiet -c "$REPO/sources-8b/md5sums"
sha256sum --quiet -c "$REPO/sources-8b/sha256sums"
echo "   all checksums OK"
# A new crates-8b.tar replaces the folder unpacked from an older one.
rm -rf $LFS/sources/crates-8b

echo "== phase 8b packages (autark-tools $(cat "$REPO/sources-8b/autark-tools.commit"))"
LFS=$LFS INSIDE=phase8b-inside.sh bash "$REPO/scripts/lfs/ch7-chroot.sh" "$@"
echo "== phase 8b done"
