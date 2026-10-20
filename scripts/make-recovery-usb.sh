#!/bin/sh
# make-recovery-usb.sh: turn a USB stick into a GParted Live boot disk plus an encrypted backup partition.
#
#   sudo make-recovery-usb.sh make   /dev/sdX <gparted-live.iso>   erase the stick and set it up
#   sudo make-recovery-usb.sh backup /dev/sdX                      copy the Ubuntu leftovers onto its encrypted partition
#   sudo make-recovery-usb.sh verify /dev/sdX                      read the backup back and check every checksum
#
# The stick ends up with two partitions:
#   1. GPARTED, 1.5 GiB FAT32: the ISO unpacked, which boots with UEFI Secure Boot on (Debian's signed shim and GRUB), so
#      the TPM keeps unlocking root. No key is enrolled for it and nothing in the firmware changes.
#   2. autark-backup, the rest: LUKS2 with a passphrase you choose (a stick gets lost, and the backup holds SSH keys).
#
# `make` erases the whole stick. It refuses anything that is not a removable USB disk, and asks you to type the device name.
# The ISO must be the one this script knows (GParted Live 1.8.1-6, sha256 below); it is checked first.

set -eu

ISO_SHA256=d789c38779f0d6f7026c12f44c2c52a04f66e28a1aea7d51f3045ad1bbf28411
ESP_SIZE=1500MiB
NAME=usb-backup
MNT=${USB_MNT:-/mnt/usb-backup}
UBUNTU=${UBUNTU_RO:-/mnt/ubuntu-ro}

die() { echo "make-recovery-usb: $*" >&2; exit 1; }
say() { echo "== $*"; }

part() {
  # /dev/sda -> /dev/sda1; /dev/mmcblk0 -> /dev/mmcblk0p1
  case $1 in *[0-9]) echo "${1}p$2" ;; *) echo "$1$2" ;; esac
}

check_stick() {
  dev=$1
  [ -b "$dev" ] || die "$dev is not a block device"
  base=${dev##*/}
  [ -e "/sys/block/$base" ] || die "$dev is not a whole disk (give /dev/sdX, not a partition)"
  [ "$(cat "/sys/block/$base/removable")" = 1 ] || die "$dev is not removable"
  readlink -f "/sys/block/$base" | grep -q '/usb' || die "$dev is not on USB"
  if grep -q "^$dev" /proc/mounts; then die "$dev has mounted partitions; unmount them first"; fi
  size=$(( $(cat "/sys/block/$base/size") * 512 ))
  [ "$size" -ge $((4 * 1073741824)) ] || die "$dev is under 4 GiB"
}

wait_for() { i=0; while [ ! -b "$1" ] && [ $i -lt 50 ]; do sleep 0.2; i=$((i + 1)); done; [ -b "$1" ] || die "$1 did not appear"; }

do_make() {
  dev=$1
  iso=$2
  check_stick "$dev"
  [ -f "$iso" ] || die "no ISO at $iso"
  say "checking the ISO"
  [ "$(sha256sum "$iso" | cut -d' ' -f1)" = "$ISO_SHA256" ] || die "$iso is not the expected GParted Live 1.8.1-6 (sha256 differs)"
  for tool in sfdisk wipefs mkfs.fat bsdtar cryptsetup mkfs.ext4; do command -v "$tool" >/dev/null || die "$tool is missing"; done
  lsblk -o NAME,SIZE,TRAN,MODEL,FSTYPE,LABEL "$dev"
  printf 'This ERASES everything on %s.\nType %s to continue: ' "$dev" "$dev"
  read -r answer
  [ "$answer" = "$dev" ] || die "not confirmed"

  say "partitioning"
  wipefs -a "$dev" >/dev/null
  sfdisk --quiet "$dev" << EOF
label: gpt
size=$ESP_SIZE, type=U, name="GPARTED"
type=L, name="autark-backup"
EOF
  p1=$(part "$dev" 1)
  p2=$(part "$dev" 2)
  wait_for "$p1"
  wait_for "$p2"

  say "GParted Live on $p1"
  mkfs.fat -F 32 -n GPARTED "$p1" >/dev/null
  mkdir -p "$MNT.esp"
  mount "$p1" "$MNT.esp"
  bsdtar -xf "$iso" -C "$MNT.esp" --no-same-owner --no-same-permissions
  sync
  [ -f "$MNT.esp/EFI/boot/bootx64.efi" ] && [ -f "$MNT.esp/live/filesystem.squashfs" ] || die "the unpacked stick is missing its boot files"
  umount "$MNT.esp"
  rmdir "$MNT.esp"

  say "encrypted backup partition $p2 (you choose the passphrase, asked twice)"
  cryptsetup luksFormat --type luks2 "$p2"
  cryptsetup open "$p2" "$NAME"
  mkfs.ext4 -q -L autark-backup "/dev/mapper/$NAME"
  cryptsetup close "$NAME"
  say "done. Boot it from the laptop's boot menu with Secure Boot left on. Next: backup $dev"
}

open_backup() {
  dev=$1
  check_stick "$dev"
  p2=$(part "$dev" 2)
  cryptsetup isLuks "$p2" || die "$p2 is not the encrypted backup partition: run make first"
  [ -e "/dev/mapper/$NAME" ] || cryptsetup open "$p2" "$NAME"
  mkdir -p "$MNT"
  grep -q " $MNT " /proc/mounts || mount "/dev/mapper/$NAME" "$MNT"
}

close_backup() {
  sync
  if grep -q " $MNT " /proc/mounts; then umount "$MNT"; fi
  if [ -e "/dev/mapper/$NAME" ]; then cryptsetup close "$NAME"; fi
}

# tar | tar keeps owners, modes and times, and lets the skipped names be listed.
copy_tree() { # source dest [tar options...]
  src=$1; dst=$2; shift 2
  mkdir -p "$dst"
  tar -C "$src" -cf - "$@" . | tar -C "$dst" -xpf -
}

do_backup() {
  dev=$1
  [ -n "${SUDO_USER:-}" ] || die "run it through sudo, from your own account: it needs to know whose home to copy"
  home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  [ -d "$home/backup-from-ubuntu" ] || die "no $home/backup-from-ubuntu"
  [ -d "$UBUNTU/home" ] || die "the Ubuntu disk is not mounted at $UBUNTU"
  uh=$(ls -d "$UBUNTU"/home/*/ | head -n 1)
  uh=${uh%/}
  open_backup "$dev"

  say "copying"
  # What the earlier scans backed up: unpushed branches, diffs, secrets, SSH/GPG keys, Windows files.
  copy_tree "$home/backup-from-ubuntu" "$MNT/backup-from-ubuntu"
  # What the Ubuntu disk holds that nothing else does. Downloads minus what can be fetched again.
  copy_tree "$uh/Downloads" "$MNT/ubuntu-home/Downloads" \
    --exclude='./postman.tar.gz' --exclude='./postman-linux-x64.tar.gz' --exclude='./Nextcloud.Talk-linux-x64.flatpak' \
    --exclude='./omii studio photos.zip' --exclude='./omii match photos + email.zip' --exclude='./Firefly*'
  [ ! -d "$uh/Pictures/Grad Photos" ] || copy_tree "$uh/Pictures/Grad Photos" "$MNT/ubuntu-home/Pictures/Grad Photos"
  [ ! -d "$uh/Documents/Gov Docs" ] || copy_tree "$uh/Documents/Gov Docs" "$MNT/ubuntu-home/Documents/Gov Docs"

  say "checksums"
  (cd "$MNT" && find . -type f ! -name MANIFEST.sha256 -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > MANIFEST.sha256)
  echo "$(wc -l < "$MNT/MANIFEST.sha256") files, $(du -sh "$MNT" | cut -f1)"
  close_backup
  say "copied. Now run: verify $dev"
}

do_verify() {
  dev=$1
  close_backup
  echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
  open_backup "$dev"
  say "reading the backup back from the stick"
  if (cd "$MNT" && sha256sum --quiet -c MANIFEST.sha256); then
    say "every file matches its checksum ($(wc -l < "$MNT/MANIFEST.sha256") files)"
    rc=0
  else
    rc=1
  fi
  close_backup
  [ "$rc" = 0 ] || die "some files do NOT match"
}

main() {
  [ "$(id -u)" = 0 ] || die "run it with sudo"
  cd /
  case ${1:-} in
    make) [ $# -eq 3 ] || die "usage: make /dev/sdX <iso>"; do_make "$2" "$3" ;;
    backup) [ $# -eq 2 ] || die "usage: backup /dev/sdX"; do_backup "$2" ;;
    verify) [ $# -eq 2 ] || die "usage: verify /dev/sdX"; do_verify "$2" ;;
    *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
  esac
}

main "$@"
