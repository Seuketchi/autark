#!/bin/bash
# Teaches the kernel the keys it logs as "Unknown key" on this laptop (hardware/target/udev/70-autark-keyboard.hwdb): today Fn+F4,
# the touchpad key, as KEY_TOUCHPAD_TOGGLE.
#
#   msi-keys-hwdb.sh check      is the mapping installed, and does udev apply it to the keyboard (any user)
#   msi-keys-hwdb.sh install    copy it to /etc/udev/hwdb.d, rebuild the hardware database and re-apply it to the input devices (root)
#   msi-keys-hwdb.sh remove     take it out again (root)
#
# As root on Autark:  su -c 'sh /home/tan/autark/scripts/msi-keys-hwdb.sh install'
# It only maps a key's code to a key name; nothing is written to the keyboard or the embedded controller.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${SRC:-$HERE/../hardware/target/udev/70-autark-keyboard.hwdb}
DEST=${DEST:-/etc/udev/hwdb.d/70-autark-keyboard.hwdb}

die() { echo "msi-keys-hwdb.sh: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" = 0 ] || die "$1 needs root (su -c 'sh $0 $1')"; }

# The keyboard's evdev node under /sys, found by name.
keyboard() {
  local dir
  for dir in /sys/class/input/input*; do
    [ "$(cat "$dir/name" 2>/dev/null)" = "AT Translated Set 2 keyboard" ] || continue
    ls -d "$dir"/event* 2>/dev/null | head -1
    return 0
  done
  return 1
}

check() {
  if [ -e "$DEST" ] && cmp -s "$SRC" "$DEST"; then echo "installed: $DEST matches the repo's file"
  elif [ -e "$DEST" ]; then echo "installed, but $DEST differs from $SRC"
  else echo "not installed ($DEST)"; fi
  local node
  node=$(keyboard) || die "no 'AT Translated Set 2 keyboard' found"
  echo "keyboard: $node"
  if /usr/bin/udevadm info -q property -p "$node" | grep '^KEYBOARD_KEY_d7=' ; then echo "udev applies the mapping to it"; else echo "udev does not apply a mapping for d7 to it (yet)"; fi
}

install_map() {
  need_root install
  [ -r "$SRC" ] || die "no $SRC"
  install -d -m 755 "$(dirname "$DEST")"
  install -m 644 "$SRC" "$DEST.new"
  mv "$DEST.new" "$DEST"
  /usr/bin/systemd-hwdb update
  /usr/bin/udevadm trigger --action=change --subsystem-match=input
  /usr/bin/udevadm settle --timeout=10 || true
  echo "installed $DEST and re-applied it to the input devices"
  check
}

remove() {
  need_root remove
  rm -f "$DEST"
  /usr/bin/systemd-hwdb update
  /usr/bin/udevadm trigger --action=change --subsystem-match=input
  echo "removed $DEST"
}

[ $# -gt 0 ] || die "usage: $0 check|install|remove"
for step in "$@"; do
  case "$step" in
    check) check ;;
    install) install_map ;;
    remove) remove ;;
    *) die "not a step: $step" ;;
  esac
done
