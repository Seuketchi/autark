#!/bin/sh
# migrate-home.sh: move /home onto a new encrypted partition (docs/storage-plan.md, "Session 1 follow-up").
#
#   migrate-home.sh check   <partition>   look at everything, change nothing
#   migrate-home.sh prepare <partition>   LUKS2-format the partition, add a recovery passphrase, make an ext4 file system
#   migrate-home.sh copy    <partition>   copy /home onto it and compare the two trees
#   migrate-home.sh switch  <partition>   point /etc/crypttab at it (the next boot uses it)
#   migrate-home.sh all     <partition>   prepare, copy and switch, asking once
#
# Run as root, on a text console with every user logged out (Ctrl+Alt+F3, log in as root): a file written while it is
# being copied can be missed. <partition> is the new, empty one, such as /dev/nvme0n1p5. Check it with lsblk first:
# prepare erases it, and refuses a partition that already has any file system or encryption on it.
#
# The new volume opens with the same key file as the old /home (/etc/cryptsetup-keys.d/autark-home.key) and takes the
# same mapper name after the switch, so /etc/fstab does not change. /home is opened by systemd after boot, not in the
# initramfs, so no boot image is rebuilt. Nothing here touches the old partition: if the new /home fails, boot to the
# emergency shell and put /etc/crypttab.bak-before-newhome-* back.

set -eu
PATH=$PATH:/usr/sbin:/sbin

KEY=${HOME_KEY:-/etc/cryptsetup-keys.d/autark-home.key}
CRYPTTAB=${CRYPTTAB:-/etc/crypttab}
OLD=autark-home
NEW=autark-home-new
MNT=${NEWHOME_MNT:-/mnt/newhome}
SRC=${HOME_SRC:-/home}
GIB=1073741824

die() { echo "migrate-home: $*" >&2; exit 1; }
say() { echo "== $*"; }

confirm() {
  printf '%s\nType %s to continue: ' "$1" "$2"
  read -r answer
  [ "$answer" = "$2" ] || die "not confirmed"
}

# The device under a mapper name, or nothing.
backing() { cryptsetup status "$1" 2>/dev/null | awk '$1 == "device:" { print $2 }'; }

mounted() { grep -q " $1 " /proc/mounts; }

used_bytes() { df -B1 --output=used "$SRC" | tail -n 1 | tr -d ' '; }

# Everything about a partition that makes it unfit, one problem at a time.
check_target() {
  dev=$1
  [ -b "$dev" ] || die "$dev is not a block device"
  base=${dev##*/}
  [ -e "/sys/class/block/$base/partition" ] || die "$dev is not a partition"
  mounted "$dev" && die "$dev is mounted"
  [ -z "$(ls "/sys/class/block/$base/holders" 2>/dev/null)" ] || [ -e "/dev/mapper/$NEW" ] || die "$dev is in use by $(ls "/sys/class/block/$base/holders")"
  for name in "$OLD" autark; do
    [ "$(backing "$name")" != "$dev" ] || die "$dev is the partition under /dev/mapper/$name"
  done
  size=$(( $(cat "/sys/class/block/$base/size") * 512 ))
  need=$(( $(used_bytes) * 2 ))
  [ "$need" -ge $((20 * GIB)) ] || need=$((20 * GIB))
  [ "$size" -ge "$need" ] || die "$dev is $((size / GIB)) GiB; at least $((need / GIB)) GiB is needed (twice what $SRC uses, 20 GiB at least)"
  [ -f "$KEY" ] || die "no key file at $KEY"
  command -v cryptsetup >/dev/null || die "cryptsetup is missing"
}

# What file system, encryption, RAID or partition table is on it, if any. A bare `blkid -p` also prints the partition's own entry
# (PART_ENTRY_*), which is not a signature, so only the types are asked for.
signature() {
  command -v blkid >/dev/null || die "blkid is missing: cannot tell whether $1 is blank"
  { blkid -p -o value -s TYPE "$1" 2>/dev/null; blkid -p -o value -s PTTYPE "$1" 2>/dev/null; } | tr '\n' ' ' | sed 's/ $//'
}

# Whether the partition is still blank, for prepare.
check_blank() {
  sig=$(signature "$1")
  [ -z "$sig" ] || die "$1 already has a file system or encryption on it ($sig). Prepare only takes an empty one."
}

report() {
  dev=$1
  echo "partition:   $dev, $(( $(cat "/sys/class/block/${dev##*/}/size") * 512 / GIB )) GiB"
  echo "old /home:   under /dev/mapper/$OLD on $(backing "$OLD"), $(( $(used_bytes) / 1048576 )) MiB used"
  echo "root:        under /dev/mapper/autark on $(backing autark)"
  echo "key file:    $KEY"
  grep -v '^#' "$CRYPTTAB" | grep "^$OLD " | sed 's/^/crypttab:    /'
  if cryptsetup isLuks "$dev" 2>/dev/null; then echo "state:       already LUKS (UUID $(blkid -s UUID -o value "$dev"))"; else echo "state:       blank"; fi
}

open_new() {
  dev=$1
  if [ ! -e "/dev/mapper/$NEW" ]; then
    cryptsetup isLuks "$dev" || die "$dev is not LUKS yet: run prepare first"
    cryptsetup open --key-file "$KEY" "$dev" "$NEW"
  fi
  [ "$(backing "$NEW")" = "$dev" ] || die "/dev/mapper/$NEW is open but not on $dev"
}

mount_new() {
  mkdir -p "$MNT"
  mounted "$MNT" || mount "/dev/mapper/$NEW" "$MNT"
}

do_prepare() {
  dev=$1
  check_target "$dev"
  check_blank "$dev"
  say "prepare $dev"
  cryptsetup luksFormat --batch-mode --type luks2 --key-file "$KEY" "$dev"
  echo "Choose a recovery passphrase for the new /home (asked twice). The key file opens it every boot;"
  echo "this passphrase is the way in if the key file is ever lost."
  cryptsetup luksAddKey --key-file "$KEY" "$dev"
  cryptsetup open --key-file "$KEY" "$dev" "$NEW"
  mkfs.ext4 -q -L autark-home2 "/dev/mapper/$NEW"
  say "prepared: LUKS UUID $(blkid -s UUID -o value "$dev")"
}

# Anything running with files open under /home.
require_quiet() {
  busy=$(fuser -m "$SRC" 2>/dev/null | tr -s ' ' '\n' | grep -v '^$' | grep -vx "$$" || true)
  [ -z "$busy" ] || {
    echo "These are using $SRC:" >&2
    # shellcheck disable=SC2086
    ps -o pid,user,args -p $(echo "$busy" | tr '\n' ',' | sed 's/,$//') >&2 || true
    die "log every user out and run this from a text console as root (Ctrl+Alt+F3)"
  }
}

# Files, symlinks and everything else with owner, mode and times, then the contents of every file.
tree_meta() {
  (
    cd "$1"
    find . -mindepth 1 -path ./lost+found -prune -o -type f -printf '%P\t%s\t%m\t%U\t%G\t%T@\n'
    find . -mindepth 1 -path ./lost+found -prune -o ! -type f -printf '%P\t%y\t%m\t%U\t%G\t%T@\t%l\n'
  ) | LC_ALL=C sort
}

tree_sums() {
  (cd "$1" && find . -path ./lost+found -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum)
}

# Both trees the same? Prints what differs and fails if not.
compare_trees() {
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  tree_meta "$1" > "$work/a.meta"
  tree_meta "$2" > "$work/b.meta"
  tree_sums "$1" > "$work/a.sum"
  tree_sums "$2" > "$work/b.sum"
  rc=0
  cmp -s "$work/a.meta" "$work/b.meta" || { echo "owners, modes, sizes or times differ:"; diff "$work/a.meta" "$work/b.meta" | head -20; rc=1; }
  cmp -s "$work/a.sum" "$work/b.sum" || { echo "file contents differ:"; diff "$work/a.sum" "$work/b.sum" | head -20; rc=1; }
  rm -rf "$work"
  trap - EXIT
  return $rc
}

do_copy() {
  dev=$1
  check_target "$dev"
  require_quiet
  say "copy $SRC to $dev"
  open_new "$dev"
  mount_new
  free=$(df -B1 --output=avail "$MNT" | tail -n 1 | tr -d ' ')
  [ "$free" -gt "$(used_bytes)" ] || die "the new file system has $((free / 1048576)) MiB free; $SRC uses $(( $(used_bytes) / 1048576 )) MiB"
  # -a keeps owners, modes, times, links, xattrs; the trailing /. includes dot files and the folder's own attributes.
  cp -a "$SRC/." "$MNT/"
  sync
  say "comparing (reads both trees in full, a minute or two)"
  compare_trees "$SRC" "$MNT" || die "the copy differs from $SRC; nothing was switched"
  say "copy verified: $(find "$MNT" -mindepth 1 -path "$MNT/lost+found" -prune -o -type f -print | wc -l) files identical"
}

# /etc/crypttab with the old volume's UUID replaced and the old line kept as a comment. $1 is the new UUID.
rewrite_crypttab() {
  awk -v name="$OLD" -v spec="UUID=$1" '
    $1 == name && $0 !~ /^[ \t]*#/ { print "# before migrate-home.sh: " $0; $2 = spec; print; next }
    { print }
  ' "$CRYPTTAB"
}

do_switch() {
  dev=$1
  cryptsetup isLuks "$dev" || die "$dev is not LUKS: run prepare and copy first"
  uuid=$(blkid -s UUID -o value "$dev")
  [ -n "$uuid" ] || die "no UUID on $dev"
  lines=$(awk -v name="$OLD" '$1 == name && $0 !~ /^[ \t]*#/' "$CRYPTTAB" | wc -l)
  [ "$lines" -eq 1 ] || die "expected one '$OLD' line in $CRYPTTAB, found $lines"
  if awk -v name="$OLD" '$1 == name && $0 !~ /^[ \t]*#/ { print $2 }' "$CRYPTTAB" | grep -qx "UUID=$uuid"; then
    say "$CRYPTTAB already points at $uuid"
  else
    say "switch $CRYPTTAB to UUID=$uuid"
    backup=$CRYPTTAB.bak-before-newhome-$(date +%Y%m%d-%H%M%S)
    cp -p "$CRYPTTAB" "$backup"
    tmp=$CRYPTTAB.new
    rewrite_crypttab "$uuid" > "$tmp"
    chmod --reference="$CRYPTTAB" "$tmp"
    mv "$tmp" "$CRYPTTAB"
    echo "backup: $backup"
  fi
  grep -v '^#' "$CRYPTTAB" | grep "^$OLD "
  if mounted "$MNT"; then umount "$MNT"; fi
  if [ -e "/dev/mapper/$NEW" ]; then cryptsetup close "$NEW"; fi
  say "done. Reboot; then check that 'df -h /home' shows the new size and your files are there."
  echo "The old partition (backing $OLD) is untouched: keep it a week before deleting it."
}

main() {
  [ "$(id -u)" = 0 ] || die "run it as root"
  [ $# -eq 2 ] || { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
  action=$1
  dev=$2
  cd /
  case $action in
    check)
      check_target "$dev"
      report "$dev"
      if cryptsetup isLuks "$dev" 2>/dev/null; then
        echo "-- looks usable for: copy and switch"
      elif [ -n "$(signature "$dev")" ]; then
        echo "-- looks usable for: nothing (it has a $(signature "$dev") signature but is not LUKS)"
      else
        echo "-- looks usable for: prepare"
      fi
      ;;
    prepare)
      check_target "$dev"; check_blank "$dev"; report "$dev"
      confirm "prepare ERASES $dev and makes it the new /home volume." "$dev"
      do_prepare "$dev"
      ;;
    copy) do_copy "$dev" ;;
    switch) do_switch "$dev" ;;
    all)
      check_target "$dev"; check_blank "$dev"; require_quiet; report "$dev"
      confirm "all ERASES $dev, copies $SRC to it, and makes the next boot use it." "$dev"
      do_prepare "$dev"
      do_copy "$dev"
      do_switch "$dev"
      ;;
    *) die "unknown action '$action' (check, prepare, copy, switch, all)" ;;
  esac
}

if [ -z "${MIGRATE_HOME_TEST:-}" ]; then main "$@"; fi
