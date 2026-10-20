#!/bin/bash
# The Rust initramfs (roadmap M4, docs/specs/autark-init.md): build the image, wrap it in a signed boot image, and add a
# firmware entry that is tried ONCE, so dracut's image stays the default and the way back in.
#
#   autark-rust-initramfs.sh build     the initramfs: autark-init, every library it and the TPM token need, as a zstd cpio
#                                      (any user; set OUT to write somewhere other than /boot)
#   autark-rust-initramfs.sh selftest  runs the staged tree in a user-namespace chroot and checks every library is there
#                                      (any user; run after build)
#   autark-rust-initramfs.sh uki       builds the signed boot image into EFI/autark-rust/ with shim beside it (root)
#   autark-rust-initramfs.sh entry     adds the firmware entry "Autark (Rust initramfs, test)" and puts BootOrder back as it was (root)
#   autark-rust-initramfs.sh try       makes the next boot start it: BootNext, and the entry first in BootOrder (root). Then run untry
#   autark-rust-initramfs.sh untry     puts BootOrder back as try found it (root); run it after the test boot, whatever happened
#   autark-rust-initramfs.sh status    what is installed and the boot order (root, to see the ESP)
#   autark-rust-initramfs.sh remove    deletes the entry, its boot image and the initramfs (root)
#
# As root on Autark:  su -c 'sh /path/to/autark-rust-initramfs.sh build uki entry'  then  su -c '... try'  and reboot (without F11: this firmware
# ignores BootNext and its F11 menu doesn't list the entry, so try puts the entry first in BootOrder instead), then  su -c '... untry'.
# Nothing here changes autark.efi, /boot/initramfs-<kver>.img, the boot order, or /etc/kernel/cmdline.
set -euo pipefail

INIT_BIN=${INIT_BIN:-/home/tan/autark-tools/target/release/autark-init}
KVER=${KVER:-$(uname -r)}
WORK=${WORK:-/var/tmp/autark-rust-initramfs}
OUT=${OUT:-/boot/initramfs-rust-$KVER.img}
ESP=${ESP:-/boot/efi}
SB=${SB:-/etc/autark/secureboot}
LABEL="Autark (Rust initramfs, test)"
ENTRY_DIR=$ESP/EFI/autark-rust
STAGE=$WORK/root

# Libraries that systemd's TPM2 token plugin loads with dlopen, so ldd on the plugin doesn't list them (same list as dracut's).
DLOPENED="/usr/lib/libtss2-esys.so.0 /usr/lib/libtss2-mu.so.0 /usr/lib/libtss2-rc.so.0 /usr/lib/libtss2-tcti-device.so.0"
PLUGIN=/usr/lib/cryptsetup/libcryptsetup-token-systemd-tpm2.so

die() { echo "autark-rust-initramfs.sh: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" = 0 ] || die "$1 needs root (su -c 'sh $0 $1')"; }
need_autark() { grep -q '^ID=autark' /etc/os-release 2>/dev/null || die "$1 only runs on Autark itself, not on the host"; }

# Copies a file to the same path under the staging tree: the parent folders are resolved (so /lib/x becomes /usr/lib/x, as
# in the merged-usr layout), and a symlink is copied as a symlink with its target following it.
copy() {
  local p=$1 dir base canon target
  dir=$(readlink -f "$(dirname "$p")")
  base=$(basename "$p")
  canon=$dir/$base
  [ -e "$STAGE$canon" ] || [ -L "$STAGE$canon" ] && return 0
  mkdir -p "$STAGE$dir"
  cp -a "$canon" "$STAGE$canon"
  if [ -L "$canon" ]; then
    target=$(readlink "$canon")
    case "$target" in
      /*) copy "$target" ;;
      *) copy "$dir/$target" ;;
    esac
  fi
}

# A file and every shared library it needs, found with ldd (which also lists the loader). With a second argument, only the libraries
# (init is installed as /init, not at the path it was built to).
closure() {
  local f=$1 lib
  [ $# -ge 2 ] || copy "$f"
  ldd "$f" 2>/dev/null | awk '/=>/ && $3 ~ /^\// {print $3} $1 ~ /^\// && $2 ~ /^\(/ {print $1}' | while read -r lib; do
    [ -e "$lib" ] && copy "$lib"
  done
}

build() {
  [ -x "$INIT_BIN" ] || die "no $INIT_BIN: build it first (cargo build --release -p autark-init in autark-tools), or set INIT_BIN"
  [ -e "$PLUGIN" ] || die "no $PLUGIN: this system has no TPM2 token plugin"
  rm -rf "$WORK"
  mkdir -p "$STAGE"/{dev,proc,sys,run,sysroot,etc,usr/lib,usr/bin,usr/sbin,lib64}
  ln -s usr/lib "$STAGE/lib"; ln -s usr/bin "$STAGE/bin"; ln -s usr/sbin "$STAGE/sbin"
  install -m 755 "$INIT_BIN" "$STAGE/init"
  closure "$INIT_BIN" libs-only
  closure "$PLUGIN"
  for lib in $DLOPENED; do closure "$lib"; done
  # The loader's own name, which the program's header asks for (here /lib64/ld-linux-x86-64.so.2).
  local interp
  interp=$(readelf -l "$INIT_BIN" | sed -n 's/.*Requesting program interpreter: \(.*\)\]/\1/p')
  [ -n "$interp" ] && copy "$interp"
  # Console and null, for the kernel to find before init runs; init mounts devtmpfs over /dev itself. Needs root; without it,
  # init still works (it opens /dev/console after the mount) and the kernel only warns.
  if [ "$(id -u)" = 0 ]; then
    mknod -m 600 "$STAGE/dev/console" c 5 1
    mknod -m 666 "$STAGE/dev/null" c 1 3
  else
    echo "note: not root, so no /dev/console and /dev/null nodes in the image (init copes)"
  fi
  mkdir -p "$(dirname "$OUT")"
  ( cd "$STAGE" && find . -print0 | LC_ALL=C sort -z | cpio --null -o -H newc --reproducible --owner=0:0 --quiet ) | zstd -q -19 -T0 -f -o "$OUT"
  echo "built $OUT ($(du -h "$OUT" | cut -f1)): $(find "$STAGE" -type f | wc -l) files"
}

# Checks the staged tree can run: every library every program in it asks for is in it, and the program starts there.
selftest() {
  [ -d "$STAGE" ] || die "run build first"
  local missing=0 f need
  while IFS= read -r f; do
    readelf -d "$f" >/dev/null 2>&1 || continue
    # Where the loader will look: /usr/lib, and the file's own RUNPATH (the TPM plugin finds libsystemd-shared that way).
    local dirs="/usr/lib" run d found
    run=$(readelf -d "$f" | sed -n 's/.*\(RUNPATH\|RPATH\).*\[\(.*\)\]/\2/p')
    for d in ${run//:/ }; do dirs="$dirs ${d//\$ORIGIN/${f#"$STAGE"}}"; done
    for need in $(readelf -d "$f" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
      found=0
      for d in $dirs; do [ -e "$STAGE$d/$need" ] && found=1; done
      [ "$found" = 1 ] || { echo "MISSING: ${f#"$STAGE"} wants $need"; missing=1; }
    done
  done < <(find "$STAGE" -type f)
  [ "$missing" = 0 ] || die "libraries are missing from the image"
  echo "every library the staged programs ask for is in the image"
  # Start it for real, in a chroot of just the staged files (a user namespace, so no root): it must get as far as reading
  # a device that isn't there, which needs the loader, libcryptsetup and everything under it.
  command -v unshare >/dev/null || { echo "no unshare: skipped the chroot run"; return 0; }
  local said
  local chroot_bin
  chroot_bin=$(command -v chroot || echo /usr/sbin/chroot)
  said=$(unshare -Ur "$chroot_bin" "$STAGE" /init check /nonexistent 2>&1 || true)
  case "$said" in
    *"autark-init:"*"/nonexistent"*) echo "the staged /init starts and reaches libcryptsetup: $said" ;;
    *) die "the staged /init didn't run as expected: $said" ;;
  esac
}

uki() {
  need_root uki; need_autark uki
  [ -s "$OUT" ] || die "no $OUT: run build first"
  [ -e "$SB/db.key" ] || die "no signing key at $SB"
  [ -e "$ESP/EFI/autark/shimx64.efi" ] || die "no shim in $ESP/EFI/autark: this is the layout Autark boots through"
  install -d "$ENTRY_DIR"
  local new=$ENTRY_DIR/grubx64.efi.new
  rm -f "$new"
  ukify build --linux="/boot/vmlinuz-$KVER-autark" \
              --initrd=/boot/microcode.img \
              --initrd="$OUT" \
              --cmdline=@/etc/kernel/cmdline \
              --os-release=@/etc/os-release \
              --uname="$KVER" \
              --signtool=systemd-sbsign \
              --no-sign-kernel \
              --secureboot-private-key="$SB/db.key" \
              --secureboot-certificate="$SB/db.crt" \
              --output="$new"
  [ -s "$new" ]
  mv "$new" "$ENTRY_DIR/grubx64.efi"
  cp "$ESP/EFI/autark/shimx64.efi" "$ESP/EFI/autark/mmx64.efi" "$ENTRY_DIR/"
  ukify inspect "$ENTRY_DIR/grubx64.efi" | grep -E '^\.(linux|initrd|cmdline|osrel|uname)|size' || true
  echo "boot image in $ENTRY_DIR (autark.efi is untouched)"
}

entry_number() { efibootmgr | sed -n "s/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} $LABEL.*/\1/p" | head -1; }

enORDER_FILE=$ENTRY_DIR/bootorder-before

# The boot order "a,b,c" with entry $1 moved to the front (added if it wasn't there).
first_in_order() {
  local rest
  rest=$(printf '%s\n' "$2" | tr ',' '\n' | grep -v -x -e "$1" -e '' | paste -sd, -)
  echo "$1${rest:+,$rest}"
}

try() {
  need_root try; need_autark try
  local n before
  n=$(entry_number)
  [ -n "$n" ] || die "no entry yet: run entry first"
  before=$(efibootmgr | sed -n 's/^BootOrder: //p')
  # Remember the order once: a second try must not save the already-changed one.
  [ -s "$ORDER_FILE" ] || echo "$before" > "$ORDER_FILE"
  efibootmgr --bootnext "$n" >/dev/null
  efibootmgr --bootorder "$(first_in_order "$n" "$(cat "$ORDER_FILE")")" >/dev/null
  echo "The next boot starts Boot$n ($LABEL): it is first in BootOrder (and BootNext), so don't press F11. Reboot now."
  echo "Afterwards run:  untry   (puts BootOrder back as it was: $(cat "$ORDER_FILE"))"
  echo "If it fails or freezes: hold the power button, then press F11 and pick plain Autark, and run untry."
}

untry() {
  need_root untry; need_autark untry
  [ -s "$ORDER_FILE" ] || die "nothing to put back: try hasn't saved a BootOrder"
  efibootmgr --bootorder "$(cat "$ORDER_FILE")" >/dev/null
  rm -f "$ORDER_FILE"
  efibootmgr | grep -E "^Boot(Current|Next|Order)"
}

status() {
  need_root status
  efibootmgr | grep -E "^Boot(Current|Next|Order)|Autark" || true
  ls -la "$ENTRY_DIR" "$OUT" 2>&1 | sed 's/^/  /'
}

remove() {
  need_root remove; need_autark remove
  local n
  n=$(entry_number)
  [ -z "$n" ] || efibootmgr -b "$n" -B >/dev/null
  rm -rf "$ENTRY_DIR" "$OUT"
  echo "removed the entry, $ENTRY_DIR and $OUT"
}

[ $# -gt 0 ] || die "usage: $0 build|selftest|uki|entry|try|untry|status|remove [more steps]"
for step in "$@"; do
  case "$step" in
    build|selftest|uki|entry|try|untry|status|remove) "$step" ;;
    *) die "not a step: $step" ;;
  esac
done
