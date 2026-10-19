#!/bin/bash
# Run this on Autark, as any user. It collects what the qemu test of autark-init needs into one tarball, to carry to a machine
# with qemu (the Ubuntu partition): the kernel, the Rust initramfs, and a small root file system for the encrypted test disk
# (a test init that checks the handover, plus systemd-cryptenroll and the libraries it needs, to enrol a TPM2 + PIN in the guest).
# Nothing here is installed or changed on Autark. See docs/specs/autark-init.md.
#
#   sh autark-init-bundle.sh            writes ~/autark-init-test-bundle.tar  (OUT=… to change)
set -euo pipefail

TOOLS=${TOOLS:-/home/tan/autark-tools}
INIT_BIN=${INIT_BIN:-$TOOLS/target/release/autark-init}
PAYLOAD=${PAYLOAD:-$TOOLS/target/release/autark-init-test-payload}
KVER=${KVER:-$(uname -r)}
KERNEL=${KERNEL:-/boot/vmlinuz-$KVER-autark}
OUT=${OUT:-$HOME/autark-init-test-bundle.tar}
HERE=$(cd "$(dirname "$0")" && pwd)
BUILD_IMAGE=$HERE/../autark-rust-initramfs.sh
# What systemd-cryptenroll loads at run time with dlopen (so ldd doesn't list it): libcryptsetup, the TSS libraries and what they use.
DLOPENED="/usr/lib/libcryptsetup.so.12 /usr/lib/libtss2-esys.so.0 /usr/lib/libtss2-mu.so.0 /usr/lib/libtss2-rc.so.0 /usr/lib/libtss2-sys.so.1 /usr/lib/libtss2-tcti-device.so.0 /usr/lib/libcrypto.so.4"

die() { echo "autark-init-bundle.sh: $*" >&2; exit 1; }
[ -x "$INIT_BIN" ] || die "no $INIT_BIN (cargo build --release -p autark-init in autark-tools)"
[ -x "$PAYLOAD" ] || die "no $PAYLOAD (cargo build --release -p autark-init in autark-tools)"
[ -r "$KERNEL" ] || die "can't read $KERNEL"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
BUNDLE=$WORK/bundle
ROOT=$BUNDLE/rootfs
mkdir -p "$ROOT"/{dev,proc,sys,run,tmp,etc,var,usr/lib,usr/bin,usr/sbin,lib64}
ln -s usr/lib "$ROOT/lib"; ln -s usr/bin "$ROOT/bin"; ln -s usr/sbin "$ROOT/sbin"

# Same copy and closure as autark-rust-initramfs.sh: resolve the parent folders, copy symlinks as symlinks with their targets after them.
STAGE=$ROOT
copy() {
  local p=$1 dir base canon target
  dir=$(readlink -f "$(dirname "$p")"); base=$(basename "$p"); canon=$dir/$base
  [ -e "$STAGE$canon" ] || [ -L "$STAGE$canon" ] && return 0
  mkdir -p "$STAGE$dir"
  cp -a "$canon" "$STAGE$canon"
  if [ -L "$canon" ]; then
    target=$(readlink "$canon")
    case "$target" in /*) copy "$target" ;; *) copy "$dir/$target" ;; esac
  fi
}
closure() {
  local f=$1 lib
  [ $# -ge 2 ] || copy "$f"
  ldd "$f" 2>/dev/null | awk '/=>/ && $3 ~ /^\// {print $3} $1 ~ /^\// && $2 ~ /^\(/ {print $1}' | while read -r lib; do [ -e "$lib" ] && copy "$lib"; done
}

# The test init, at the root of the test disk (the kernel command line says init=/test-payload).
install -m 755 "$PAYLOAD" "$ROOT/test-payload"
closure "$PAYLOAD" libs-only
interp=$(readelf -l "$PAYLOAD" | sed -n 's/.*Requesting program interpreter: \(.*\)\]/\1/p'); [ -n "$interp" ] && copy "$interp"
# systemd-cryptenroll, to enrol the TPM2 + PIN from inside the guest, where the (software) TPM is.
closure /usr/bin/systemd-cryptenroll
for lib in $DLOPENED; do [ -e "$lib" ] && closure "$lib"; done

# Does it run there? It must start, and find the TSS libraries it loads with dlopen ("not installed" means it didn't).
said=$(unshare -Ur /usr/sbin/chroot "$ROOT" /usr/bin/systemd-cryptenroll --tpm2-device=list 2>&1 || true)
case "$said" in
  *"not installed"*|*"cannot open shared object"*|*"No such file"*) die "systemd-cryptenroll can't load what it needs in the test root: $said" ;;
esac
echo "systemd-cryptenroll starts in the test root: $(echo "$said" | head -1)"

# The initramfs under test, built the way it would be for the laptop (as this user, so without the /dev nodes: the stricter case).
WORK_INITRAMFS=$WORK/initramfs OUT_INITRAMFS=$BUNDLE/initramfs-rust.img
WORK=$WORK_INITRAMFS OUT=$OUT_INITRAMFS INIT_BIN=$INIT_BIN KVER=$KVER bash "$BUILD_IMAGE" build selftest | tail -4

cp "$KERNEL" "$BUNDLE/vmlinuz"
{
  echo "kernel $KVER ($(basename "$KERNEL"))"
  echo "built $(date -u +%FT%TZ) from autark-init $(sha256sum "$INIT_BIN" | cut -c1-16)"
  (cd "$BUNDLE" && sha256sum vmlinuz initramfs-rust.img)
} > "$BUNDLE/MANIFEST"
tar -C "$BUNDLE" -cf "$OUT" .
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
echo "Copy it to the machine with qemu and run: sudo python3 autark-init-qemu-test.py $(basename "$OUT")"
