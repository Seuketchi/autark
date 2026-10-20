#!/bin/bash
# After a kernel update: everything that has to be redone for the NEW kernel once you have booted it. A kernel build wipes
# /usr/lib/modules/<kver>/updates, so the out-of-tree drivers (msi-ec for the fans, charge limit and keyboard backlight; nouveau for the
# GPU) are gone, and the Rust init's boot image (the default boot) is for the old kernel. This runs the existing scripts in the right order:
#
#   autark-kernel-post.sh check     what is and isn't in place for the running kernel (any user; the ESP needs root, so it isn't looked at)
#   autark-kernel-post.sh build     compile msi-ec and nouveau for it, build autark-init from autark-tools' main, check the init image (any user)
#   autark-kernel-post.sh install   sign and install both drivers and load them, then build the Rust boot image and make it the default (root)
#
# The usual sequence, from the new kernel (the kernel install itself, kernel-install.sh-style, comes first and boots through dracut):
#   bash scripts/autark-kernel-post.sh check build
#   su -c 'bash scripts/autark-kernel-post.sh install'   (from the repository's root)
#   autark-hw doctor            "Every device that needs a driver has one", then reboot once to start the Rust init for this kernel
#
# NO_DEFAULT=1 installs the drivers and builds the Rust image but leaves the normal entry alone: try it first with
#   su -c 'bash …/autark-rust-initramfs.sh try'   (reboot, look, then untry), and promote it with  …/autark-rust-initramfs.sh default.
# Refuses to install an init that isn't autark-tools' main, or a Rust image over a dracut image that isn't for this kernel.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
KVER=${KVER:-$(uname -r)}
TOOLS=${TOOLS:-$HOME/autark-tools}
TARBALL=${TARBALL:-/sources/linux-$KVER.tar.xz}
NOUVEAU_TREE_ROOT=${NOUVEAU_TREE_ROOT:-/var/tmp/autark-nouveau-src}   # holds only drivers/gpu/drm/nouveau, taken out of the tarball
INIT_WORK=${INIT_WORK:-/var/tmp/autark-rust-initramfs-user}           # the any-user build and selftest; root's build uses the script's own
ESP=${ESP:-/boot/efi}
# What the default boot image's command line gets on top of /etc/kernel/cmdline: the splash, a quiet console, and the log on the ESP.
EXTRA_CMDLINE=${EXTRA_CMDLINE:-autark.splash=1 quiet loglevel=3 vt.global_cursor_default=0 autark.log=/dev/nvme0n1p6}
UPDATES=/usr/lib/modules/$KVER/updates

die() { echo "autark-kernel-post.sh: $*" >&2; exit 1; }
say() { echo; echo "== $*"; }
need_root() { [ "$(id -u)" = 0 ] || die "$1 needs root (su -c 'bash $0 $1')"; }

# Is the module in updates/ built for this kernel? (No -q after a pipe: grep -q + pipefail reports a found line as missing.)
module_ok() {
  local ko=$UPDATES/$1.ko vermagic
  [ -e "$ko" ] || return 1
  vermagic=$(/usr/sbin/modinfo -F vermagic "$ko" 2>/dev/null) || return 1
  case "$vermagic" in "$KVER "*) return 0 ;; *) return 1 ;; esac
}

check() {
  say "kernel $KVER"
  local todo=0
  for m in msi-ec nouveau; do
    if module_ok "$m"; then echo "ok       $m is installed for $KVER"; else echo "MISSING  $m for $KVER"; todo=1; fi
  done
  local img=/boot/initramfs-rust-$KVER.img init=$TOOLS/target/release/autark-init
  if [ ! -s "$img" ]; then echo "MISSING  the Rust init image for $KVER ($img)"; todo=1
  elif [ -e "$init" ] && [ "$init" -nt "$img" ]; then echo "STALE    $img is older than the autark-init built in $TOOLS"; todo=1
  else echo "ok       the Rust init image for $KVER exists ($(date -r "$img" '+%F %T'))"; fi
  echo "         (which init the normal entry boots: su -c 'bash $HERE/autark-rust-initramfs.sh status | head -3')"
  [ "$todo" = 0 ] && echo "nothing to do" || echo "to do: bash $0 build, then su -c 'bash $0 install'"
}

# nouveau's source is only the driver's own folder, taken out of the kernel tarball the running kernel was built from.
nouveau_tree() {
  local tree=$NOUVEAU_TREE_ROOT/linux-$KVER
  if [ ! -d "$tree/drivers/gpu/drm/nouveau" ]; then
    [ -r "$TARBALL" ] || die "no kernel source at $TARBALL (set TARBALL=…)"
    echo "taking nouveau out of $TARBALL (sha256 $(sha256sum "$TARBALL" | cut -d' ' -f1); /sources has no recorded checksum for it)" >&2
    mkdir -p "$NOUVEAU_TREE_ROOT"
    tar -xf "$TARBALL" -C "$NOUVEAU_TREE_ROOT" "linux-$KVER/drivers/gpu/drm/nouveau"
  fi
  [ -d "$tree/drivers/gpu/drm/nouveau" ] || die "no nouveau source in $tree"
  echo "$tree"
}

# autark-init must be what is on main: this becomes the default boot, so not an unmerged branch or uncommitted edits.
init_source_ok() {
  [ -d "$TOOLS/.git" ] || die "no autark-tools at $TOOLS (set TOOLS=…)"
  local branch
  branch=$(git -C "$TOOLS" rev-parse --abbrev-ref HEAD)
  [ "$branch" = main ] || die "autark-tools is on '$branch', not main: switch it (git -C $TOOLS checkout main && git -C $TOOLS pull)"
  [ -z "$(git -C "$TOOLS" status --porcelain --untracked-files=no)" ] || die "autark-tools has uncommitted changes"
}

build() {
  [ "$(id -u)" != 0 ] || die "build runs as your own user (root installs what you built)"
  init_source_ok   # first, so a wrong branch stops it before the long compile
  say "msi-ec for $KVER"
  KVER=$KVER bash "$HERE/msi-ec-module.sh" build check
  say "nouveau for $KVER (low priority, pauses itself when hot)"
  local tree
  tree=$(nouveau_tree)
  KVER=$KVER SRC_TREE=$tree bash "$HERE/nouveau-module.sh" build check
  say "autark-init from autark-tools main ($(git -C "$TOOLS" log -1 --format='%h %s'))"
  (cd "$TOOLS" && cargo build --release -p autark-init --offline 2>&1 | tail -2)
  [ -x "$TOOLS/target/release/autark-init" ] || die "no autark-init was built"
  say "the init image, built and checked without root"
  KVER=$KVER INIT_BIN=$TOOLS/target/release/autark-init WORK=$INIT_WORK OUT=$INIT_WORK/initramfs-rust-$KVER.img bash "$HERE/autark-rust-initramfs.sh" build selftest
  echo
  echo "built. Now, as root:  su -c 'bash $0 install'"
}

install_all() {
  need_root install
  # The way back must be right before anything is promoted: dracut's image for THIS kernel (the kernel install makes it).
  if [ "${NO_DEFAULT:-0}" != 1 ]; then
    [ -s "$ESP/EFI/Linux/autark.efi" ] || die "no $ESP/EFI/Linux/autark.efi (dracut's image, the fallback)"
    ukify inspect "$ESP/EFI/Linux/autark.efi" | grep "$KVER" >/dev/null || die "dracut's image in $ESP/EFI/Linux isn't for $KVER: install the kernel's boot image first (or NO_DEFAULT=1)"
  fi
  init_source_ok_root
  say "msi-ec: sign, install, load"
  KVER=$KVER bash "$HERE/msi-ec-module.sh" install load
  # msi-ec has no alias, so nothing loads it by itself after a reboot (the fan modes, charge limit and keyboard backlight would be missing).
  # Loading only reads from the controller. A failure to load (e.g. before a new kernel's driver is built) is logged and harmless.
  if [ ! -e /etc/modules-load.d/msi-ec.conf ]; then
    install -d -m 755 /etc/modules-load.d
    echo msi-ec > /etc/modules-load.d/msi-ec.conf
    echo "added /etc/modules-load.d/msi-ec.conf: msi-ec now loads at every boot"
  fi
  say "nouveau: sign, install, load"
  KVER=$KVER SRC_TREE=$NOUVEAU_TREE_ROOT/linux-$KVER bash "$HERE/nouveau-module.sh" install load
  say "the Rust init image for $KVER"
  local steps="build uki"
  [ "${NO_DEFAULT:-0}" = 1 ] || steps="$steps default"
  KVER=$KVER INIT_BIN=$TOOLS/target/release/autark-init EXTRA_CMDLINE=$EXTRA_CMDLINE bash "$HERE/autark-rust-initramfs.sh" $steps
  echo
  if [ "${NO_DEFAULT:-0}" = 1 ]; then
    echo "drivers installed; the Rust image is built but the normal entry is unchanged (try, then default: see the top of this script)"
  else
    echo "done: the drivers are loaded and the normal Autark entry boots the Rust init for $KVER."
  fi
  echo "now, as yourself:  autark-hw doctor     and reboot once (F11 → Autark) to boot the new image"
}

# Root can read the checkout too, but git refuses a repository owned by someone else, so ask as that owner.
init_source_ok_root() {
  [ -x "$TOOLS/target/release/autark-init" ] || die "no $TOOLS/target/release/autark-init: run build first, as yourself"
  local owner
  owner=$(stat -c %U "$TOOLS")
  [ "$(su "$owner" -s /bin/sh -c "git -C '$TOOLS' rev-parse --abbrev-ref HEAD" 2>/dev/null || true)" = main ] || die "autark-tools isn't on main: run build as yourself first"
}

[ $# -gt 0 ] || die "usage: $0 check|build|install [more steps]"
for step in "$@"; do
  case "$step" in
    check) check ;;
    build) build ;;
    install) install_all ;;
    *) die "not a step: $step" ;;
  esac
done
