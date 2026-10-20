#!/bin/bash
# make-installer-image.sh: build the installer USB image from a release rootfs (docs/specs/installer.md). It is a disk
# image to write to a stick (dd, or any imaging tool) or to boot in qemu (scripts/qemu-test/install-test.sh):
#
#   p1  ESP, FAT32     EFI/BOOT/BOOTX64.EFI: the live system's kernel and initramfs as one EFI file (not signed, so
#                      Secure Boot must be off on the machine while it boots the stick)
#   p2  ext4 AUTARK-LIVE   LiveOS/rootfs.img: the live system (the release rootfs, signed in as autark-install and
#                      the public key), and autark/: the rootfs tarball, its signature and checksums, for the installer
#
#   sudo scripts/make-installer-image.sh --rootfs autark-rootfs-0.1.tar.zst --version 0.1 --pubkey autark-release.pub \
#                                        [--out FILE] [--installer scripts/autark-install.sh] [--dry-run]
#
# It is an image and not an ISO because it needs only tools every build machine has (sfdisk, mkfs.vfat, mke2fs, dracut,
# ukify); an ISO builder comes with libisoburn or squashfs-tools later. Needs root (loop mounts). --rootfs must be the
# tarball make-rootfs.sh made; its .minisig (make-rootfs --sign) is copied beside it. Without --pubkey the image can only
# install with --no-verify. Staging needs about 3 times the rootfs size: set TMPDIR to a folder with room. The live system boots to a root prompt on the first console, and tells you to run
# autark-install; it has no password and no network login, and nothing in it is written to the disk.
set -euo pipefail

export PATH=$PATH:/usr/sbin:/sbin
ROOTFS= VERSION= OUT= PUBKEY= INSTALLER= DRY=0
HERE=$(cd "$(dirname "$0")" && pwd)
die() { echo "make-installer-image: $*" >&2; exit 1; }
usage() { sed -n '2,/^set -e/p' "$0" | sed '$d;s/^# \{0,1\}//' >&2; exit 2; }
while [ $# -gt 0 ]; do
  case $1 in
    --rootfs) ROOTFS=${2:?}; shift ;;
    --version) VERSION=${2:?}; shift ;;
    --out) OUT=${2:?}; shift ;;
    --pubkey) PUBKEY=${2:?}; shift ;;
    --installer) INSTALLER=${2:?}; shift ;;
    --dry-run|-n) DRY=1 ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
  shift
done
[ -n "$ROOTFS" ] && [ -n "$VERSION" ] || usage
[[ $VERSION =~ ^[0-9A-Za-z._-]+$ ]] || die "version: letters, digits, . _ -"
[ -f "$ROOTFS" ] || die "no such rootfs: $ROOTFS"
[ -z "$PUBKEY" ] || [ -f "$PUBKEY" ] || die "no such public key: $PUBKEY"
[ -n "$INSTALLER" ] || INSTALLER=$HERE/autark-install.sh
[ -f "$INSTALLER" ] || die "no installer script: $INSTALLER"
[ -n "$OUT" ] || OUT=autark-installer-$VERSION.img
need=(sfdisk mkfs.vfat mke2fs dracut ukify losetup zstd tar du truncate)
for t in "${need[@]}"; do command -v "$t" > /dev/null || die "missing tool: $t"; done
[ "$DRY" = 1 ] || [ "$(id -u)" = 0 ] || die "needs root (loop mounts); --dry-run shows the plan"

if [ "$DRY" = 1 ]; then
  echo "would unpack $ROOTFS, add the installer and live-boot settings, and write $OUT (ESP + AUTARK-LIVE with"
  echo "LiveOS/rootfs.img and autark/$(basename "$ROOTFS")${PUBKEY:+, autark/autark-release.pub})"
  exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/var/tmp}/autark-installer.XXXXXX")
LOOP= ESPMNT=$WORK/esp DATAMNT=$WORK/data
cleanup() {
  mountpoint -q "$ESPMNT" 2> /dev/null && umount "$ESPMNT"
  mountpoint -q "$DATAMNT" 2> /dev/null && umount "$DATAMNT"
  [ -z "$LOOP" ] || losetup -d "$LOOP" 2> /dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$WORK/root" "$ESPMNT" "$DATAMNT"

echo "== unpacking $(basename "$ROOTFS") as the live system"
zstd -dc "$ROOTFS" | tar -x -C "$WORK/root" --numeric-owner --xattrs --acls -p
ROOT=$WORK/root
KVER=$(ls "$ROOT/usr/lib/modules" | sort -V | tail -1)
[ -n "$KVER" ] && [ -s "$ROOT/boot/vmlinuz-$KVER-autark" ] || die "the rootfs has no kernel (usr/lib/modules, boot/vmlinuz-*-autark)"

echo "== live-system settings (this copy only; the tarball is untouched)"
install -m 0755 "$INSTALLER" "$ROOT/usr/local/bin/autark-install"
install -d "$ROOT/etc/autark"
[ -z "$PUBKEY" ] || install -m 0644 "$PUBKEY" "$ROOT/etc/autark/installer-release.pub"
# Console login as root with no password, on every console that has no user logged in; the machine is the stick's.
install -d "$ROOT/etc/systemd/system/getty@tty1.service.d" "$ROOT/etc/systemd/system/serial-getty@ttyS0.service.d"
printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty -o "-p -f -- \\\\u" --noclear --autologin root %%I $TERM\n' \
  > "$ROOT/etc/systemd/system/getty@tty1.service.d/live.conf"
printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty -o "-p -f -- \\\\u" --keep-baud --autologin root 115200,57600,38400,9600 %%I $TERM\n' \
  > "$ROOT/etc/systemd/system/serial-getty@ttyS0.service.d/live.conf"
ln -sfn /usr/lib/systemd/system/multi-user.target "$ROOT/etc/systemd/system/default.target"
cat > "$ROOT/etc/motd" << 'EOF'

  Autark installer. Nothing on this stick is written to your disks until you run:

      autark-install --disk /dev/nvme0n1 --rootfs /run/initramfs/live/autark/ROOTFS \
                     --pubkey /etc/autark/installer-release.pub --hostname NAME --user NAME

  (lsblk shows the disks; autark-install --help lists the options. It asks you to type the disk's name to confirm.)

EOF
sed -i "s|ROOTFS|$(basename "$ROOTFS")|" "$ROOT/etc/motd"
rm -f "$ROOT/etc/machine-id"

echo "== boot image for the live system"
INITRD=$WORK/initramfs.img
dracut --force --no-hostonly --kver "$KVER" --kmoddir "$ROOT/usr/lib/modules/$KVER" \
  --add "dmsquash-live" --omit "plymouth" "$INITRD" > /dev/null
CMDLINE='root=live:LABEL=AUTARK-LIVE rd.live.image rd.live.overlay.overlayfs=1 rw console=tty0 console=ttyS0,115200 loglevel=4'
ukify build --linux="$ROOT/boot/vmlinuz-$KVER-autark" --initrd="$INITRD" --cmdline="$CMDLINE" \
  --os-release=@"$ROOT/etc/os-release" --uname="$KVER" --output="$WORK/BOOTX64.EFI"

echo "== live root filesystem"
USED=$(du -s --block-size=1M "$ROOT" | cut -f1)
IMG=$WORK/rootfs.img
truncate -s "$((USED * 12 / 10 + 256))M" "$IMG"
mke2fs -q -t ext4 -L autark-live-root -d "$ROOT" "$IMG"

echo "== disk image $OUT"
ESPMB=$(( $(stat -c %s "$WORK/BOOTX64.EFI") / 1048576 + 64 ))
TARMB=$(( ($(stat -c %s "$ROOTFS") + 1048575) / 1048576 ))
DATAMB=$(( $(stat -c %s "$IMG") / 1048576 + TARMB + 256 ))
rm -f "$OUT"; truncate -s "$((ESPMB + DATAMB + 4))M" "$OUT"
sfdisk -q "$OUT" << EOF
label: gpt
start=1MiB, size=${ESPMB}MiB, type=U, name="AUTARK-ESP"
size=${DATAMB}MiB, type=L, name="AUTARK-LIVE"
EOF
LOOP=$(losetup --find --show --partscan "$OUT")
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -b "${LOOP}p2" ] && break; sleep 0.3; done
[ -b "${LOOP}p2" ] || die "the loop device ${LOOP} has no partitions"
mkfs.vfat -F 32 -n AUTARKESP "${LOOP}p1" > /dev/null
mke2fs -q -t ext4 -L AUTARK-LIVE "${LOOP}p2"
mount "${LOOP}p1" "$ESPMNT"; mount "${LOOP}p2" "$DATAMNT"
install -d "$ESPMNT/EFI/BOOT" "$DATAMNT/LiveOS" "$DATAMNT/autark"
install -m 0644 "$WORK/BOOTX64.EFI" "$ESPMNT/EFI/BOOT/BOOTX64.EFI"
install -m 0644 "$IMG" "$DATAMNT/LiveOS/rootfs.img"
install -m 0644 "$ROOTFS" "$DATAMNT/autark/"
[ ! -f "$ROOTFS.minisig" ] || install -m 0644 "$ROOTFS.minisig" "$DATAMNT/autark/"
[ -z "$PUBKEY" ] || install -m 0644 "$PUBKEY" "$DATAMNT/autark/autark-release.pub"
( cd "$DATAMNT/autark" && sha256sum -- * > SHA256SUMS )
sync
echo "== $OUT: $(du -h --apparent-size "$OUT" | cut -f1) ($(basename "$ROOTFS"), kernel $KVER)"
