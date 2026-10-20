#!/bin/bash
# Build guide Step 4, part 2: LFS 13.1-systemd chapter 7, the host side, as root.
# Changes $LFS's owner to root (7.2), mounts the virtual filesystems (7.3), runs ch7-inside.sh in the
# chroot (7.4–7.14), unmounts them whatever happens, and with `backup` writes the chapter 7 checkpoint.
# Usage: sudo LFS=/mnt/lfs bash scripts/lfs/ch7-chroot.sh [inside phase...]
#        KVER=7.2.11 passes the kernel version to ch10-kernel-inside.sh and step6-boot-inside.sh (default 7.2.11)
#        sudo LFS=/mnt/lfs INSIDE=ch8-inside.sh bash scripts/lfs/ch7-chroot.sh [package...]   (chapter 8)
#        sudo LFS=/mnt/lfs bash scripts/lfs/ch7-chroot.sh backup <file.tar.xz>
set -euo pipefail

LFS=${LFS:?set LFS=/mnt/lfs}
here=$(cd "$(dirname "$0")" && pwd)
inside=${INSIDE:-ch7-inside.sh}
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
mountpoint -q "$LFS" || { echo "$LFS is not mounted (see build guide Step 1)" >&2; exit 1; }

# 7.14, after leaving the chroot: unmount in the book's order. Safe to call when nothing is mounted.
unmount_kernfs() {
  mountpoint -q $LFS/dev/shm && umount $LFS/dev/shm
  mountpoint -q $LFS/dev/pts && umount $LFS/dev/pts
  for m in sys proc run dev; do mountpoint -q $LFS/$m && umount $LFS/$m; done
  return 0
}

if [ "${1:-}" = backup ]; then
  out=${2:?usage: ch7-chroot.sh backup <file.tar.xz>}
  unmount_kernfs
  cd $LFS
  # The book's `tar -cJpf`, with xz on every core.
  tar -I 'xz -T0' -cpf "$out" .
  echo "== backup: $(du -h "$out" | cut -f1) at $out"
  exit 0
fi

# 7.2 (--from lfs only touches files lfs still owns, so a re-run changes nothing)
# Only while the build user exists: after the host cleanup removed `lfs`, `chown --from lfs` fails
# ("invalid user"), and there is nothing left for it to change anyway.
if getent passwd lfs > /dev/null; then
  chown --from lfs -R root:root $LFS/{usr,var,etc}
  [ -d $LFS/tools ] && chown --from lfs -R root:root $LFS/tools
  case $(uname -m) in
    x86_64) chown --from lfs -R root:root $LFS/lib64 ;;
  esac
fi

# 7.3
mkdir -pv $LFS/{dev,proc,sys,run}
trap unmount_kernfs EXIT
mountpoint -q $LFS/dev     || mount -v --bind /dev $LFS/dev
mountpoint -q $LFS/dev/pts || mount -vt devpts devpts -o gid=5,mode=0620 $LFS/dev/pts
mountpoint -q $LFS/proc    || mount -vt proc proc $LFS/proc
mountpoint -q $LFS/sys     || mount -vt sysfs sysfs $LFS/sys
mountpoint -q $LFS/run     || mount -vt tmpfs tmpfs $LFS/run
if [ -h $LFS/dev/shm ]; then
  install -v -d -m 1777 $LFS$(realpath /dev/shm)
else
  mountpoint -q $LFS/dev/shm || mount -vt tmpfs -o nosuid,nodev tmpfs $LFS/dev/shm
fi

# 7.4: the book's chroot command, running the inside script instead of an interactive login shell.
install -m 0755 "$here/$inside" "$here/build-lib.sh" $LFS/sources/
chroot "$LFS" /usr/bin/env -i   \
    HOME=/root                  \
    TERM="${TERM:-xterm}"       \
    PATH=/usr/bin:/usr/sbin     \
    ${KVER:+KVER="$KVER"}       \
    MAKEFLAGS="-j$(nproc)"      \
    TESTSUITEFLAGS="-j$(nproc)" \
    /bin/bash "/sources/$inside" "$@"
