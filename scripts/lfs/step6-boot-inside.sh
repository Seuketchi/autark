#!/bin/bash
# Build guide Step 6.3 and 6.5: firmware, CPU microcode, initramfs (dracut) and the unified kernel image (ukify).
# Runs INSIDE the chroot as root, started by ch7-chroot.sh with INSIDE=step6-boot-inside.sh, after the kernel
# (ch10-kernel-inside.sh) is installed. The image is signed with Autark's own Secure Boot db key.
# What belongs to the machine comes from the hardware profile that scripts/lfs/stage-profile.sh staged in /sources:
#   profile-boot.env        ROOT_LUKS_UUID (required), and CPU_UCODE, the one microcode file for the CPU (optional)
#   profile-firmware.list   optional: the firmware files the machine loads, relative to the linux-firmware tree
# Without a firmware list the whole linux-firmware tree is installed; without CPU_UCODE the early microcode image
# carries every Intel and AMD file, and the kernel picks the one that matches the CPU.
# Sources and how each was verified: log.md, 2026-10-17 "Step 6".
set -euo pipefail

if [ ! -e /sources/wget-list-systemd ] || grep -qi ubuntu /etc/os-release 2>/dev/null; then
  echo "step6-boot-inside.sh: not inside the Autark chroot; refusing to run" >&2
  exit 1
fi

KVER=${KVER:-7.2.11}
FW=linux-firmware-20260916
UCODE=Intel-Linux-Processor-Microcode-Data-Files-microcode-20260925

ROOT_LUKS_UUID=; CPU_UCODE=
[ ! -e /sources/profile-boot.env ] || source /sources/profile-boot.env
[ -n "$ROOT_LUKS_UUID" ] || { echo "step6-boot-inside.sh: no ROOT_LUKS_UUID; run scripts/lfs/stage-profile.sh with --luks-uuid" >&2; exit 1; }

logs=/sources/logs
mkdir -p "$logs" /sources/.done /sources/.track /var/lib/autark/files
srcdir=/sources
source "$(dirname "$0")/build-lib.sh"

export CFLAGS="-O2 -march=x86-64-v3 -pipe -fstack-protector-strong -fstack-clash-protection -fcf-protection=full -D_FORTIFY_SOURCE=3"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-Wl,-O1 -Wl,-z,relro -Wl,-z,now"

snapshot() {
  find / -xdev \( -path /sources -o -path /tmp -o -path /root -o -path /var/lib/autark \) -prune \
    -o \( -type f -o -type l \) -print | LC_ALL=C sort
}

run_pkg() {
  local name=$1 tarball=$2 fn=$3
  if [ -e "/sources/.done/boot-$name" ]; then echo "== $name: already done, skipped"; return; fi
  snapshot > /sources/.track/before
  if [ "$tarball" = - ]; then
    echo "== $fn: started $(date +%T)"
    set +e; ( set -e; cd /sources; "$fn" ) > "$logs/$fn.log" 2>&1; local rc=$?; set -e
    if [ "$rc" != 0 ]; then echo "== $fn: FAILED (exit $rc)"; tail -25 "$logs/$fn.log"; exit 1; fi
    echo "== $fn: done"
  else
    build "$tarball" "$fn"
  fi
  snapshot | LC_ALL=C comm -13 /sources/.track/before - > "/var/lib/autark/files/$name"
  echo "   $(wc -l < "/var/lib/autark/files/$name") new files tracked"
  touch "/sources/.done/boot-$name"
}

# BLFS cpio, without the optional HTML/PDF documentation.
pkg_cpio() {
  sed -e "/^extern int (\*xstat)/s/()/(const char * restrict,  struct stat * restrict)/" \
      -i src/extern.h
  sed -e "/^int (\*xstat)/s/()/(const char * restrict,  struct stat * restrict)/" \
      -i src/global.c
  ./configure --prefix=/usr \
              --enable-mt   \
              --with-rmt=/usr/libexec/rmt &&
  make
  make install
}

# The profile's firmware (hardware/<profile>/firmware.list), or all of linux-firmware without a list, plus the
# old-name links linux-firmware's WHENCE defines for Wi-Fi. SOF audio firmware isn't in linux-firmware (sof-bin,
# before Step 7b).
step_firmware() {
  local t list=/sources/profile-firmware.list; t=$(mktemp -d)
  local -a wanted=()
  [ ! -s "$list" ] || mapfile -t wanted < <(grep -vE '^[[:space:]]*(#|$)' "$list")
  if [ "${#wanted[@]}" -gt 0 ]; then
    tar -xJf /sources/$FW.tar.xz -C "$t" --wildcards "${wanted[@]/#/$FW/}"
  else
    tar -xJf /sources/$FW.tar.xz -C "$t"
  fi
  ( cd "$t/$FW" && find . -type f -exec install -vDm644 {} /usr/lib/firmware/{} \; )
  for f in "$t/$FW"/intel/iwlwifi/iwlwifi-*; do
    [ -e "$f" ] || continue
    ln -sfv "intel/iwlwifi/$(basename "$f")" "/usr/lib/firmware/$(basename "$f")"
  done
  rm -rf "$t"
}

# CPU microcode, and an early-load cpio that the boot image puts first, so the microcode loads before anything
# else (build guide 6.5). The CPU itself rejects microcode its vendor didn't sign. With CPU_UCODE set only that
# Intel file is used; without it the cpio carries every Intel file and every AMD file linux-firmware installed.
step_microcode() {
  local t early; t=$(mktemp -d); early=$t/early/kernel/x86/microcode
  mkdir -p "$early"
  if [ -n "$CPU_UCODE" ]; then
    tar -xzf /sources/intel-microcode-20260925.tar.gz -C "$t" "$UCODE/intel-ucode/$CPU_UCODE"
    install -vDm644 "$t/$UCODE/intel-ucode/$CPU_UCODE" /usr/lib/firmware/intel-ucode/$CPU_UCODE
    cp "$t/$UCODE/intel-ucode/$CPU_UCODE" "$early/GenuineIntel.bin"
  else
    tar -xzf /sources/intel-microcode-20260925.tar.gz -C "$t" "$UCODE/intel-ucode"
    install -vDm644 -t /usr/lib/firmware/intel-ucode "$t/$UCODE"/intel-ucode/*
    cat "$t/$UCODE"/intel-ucode/* > "$early/GenuineIntel.bin"
    if ls /usr/lib/firmware/amd-ucode/microcode_amd*.bin > /dev/null 2>&1; then
      cat /usr/lib/firmware/amd-ucode/microcode_amd*.bin > "$early/AuthenticAMD.bin"
    fi
  fi
  ( cd "$t/early" && find . | cpio -o -H newc --reproducible ) > /boot/microcode.img
  rm -rf "$t"
}


# dracut-ng (not in BLFS). No man pages (need asciidoc), no Rust cpio helper (no rustc yet).
pkg_dracut() {
  ./configure --prefix=/usr                  \
              --sysconfdir=/etc              \
              --libdir=/usr/lib              \
              --systemdsystemunitdir=/usr/lib/systemd/system \
              --disable-documentation        \
              --disable-dracut-cpio
  make
  make install
}

# The initramfs: systemd-based, with LUKS (systemd-cryptsetup) and TPM2. Not host-only: built in a chroot,
# host-only detection would see the build machine's loop device instead of the laptop's NVMe. The unlock path
# is built into the kernel anyway (ch10-kernel-inside.sh), so modules here are only extras.
step_initramfs() {
  install -d /etc/dracut.conf.d /etc/kernel
  cat > /etc/dracut.conf.d/autark.conf << "EOF"
hostonly="no"
add_dracutmodules+=" systemd systemd-cryptsetup "
# systemd-cryptsetup loads the TSS libraries itself (dlopen) for TPM unlock; dracut's tpm2-tss module would
# require the separate tpm2-tools CLI, so the libraries go in directly instead.
install_items+=" /usr/lib/libtss2-esys.so.0 /usr/lib/libtss2-mu.so.0 /usr/lib/libtss2-rc.so.0 /usr/lib/libtss2-tcti-device.so.0 "
# systemd-cryptsetup unlocks TPM2 and recovery tokens through cryptsetup token plugins; without them in the initramfs
# it silently skips the TPM ("falling back to traditional unlocking", found in a debug run, log.md).
install_items+=" /usr/lib/cryptsetup/libcryptsetup-token-systemd-tpm2.so "
# (systemd builds no plugin for the recovery key: it unlocks like a passphrase.)
omit_dracutmodules+=" network nfs iscsi multipath lvm mdraid dmraid "
compress="zstd"
early_microcode="no"
EOF
  dracut --force --kver $KVER /boot/initramfs-$KVER.img
  lsinitrd /boot/initramfs-$KVER.img | grep -E 'systemd-cryptsetup|libtss2|cryptsetup.target|systemd-sysusers' | head -8
}

# Secure Boot key (build guide 6.5, "your own keys"): one db key that signs Autark's boot images. RSA-2048 for the
# widest firmware support. The private key stays on the encrypted root, root-only; the public certificate also goes
# on the EFI partition, where the firmware's setup screen can read it to enroll (Step 7b). Created once, never
# overwritten: a new key would need enrolling again.
SB=/etc/autark/secureboot
step_secureboot_key() {
  install -d -m 0700 $SB
  if [ ! -s $SB/db.key ]; then
    openssl req -new -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
      -subj "/CN=Autark Secure Boot db 2026/" -keyout $SB/db.key -out $SB/db.crt
  fi
  chmod 0400 $SB/db.key
  openssl x509 -in $SB/db.crt -outform DER -out $SB/db.der
  install -D -m 0644 $SB/db.der /boot/efi/EFI/autark/autark-db.der
  openssl x509 -in $SB/db.crt -noout -subject -enddate -fingerprint -sha256
}

# The unified kernel image: microcode first, then the initramfs, the kernel and its command line, in one
# EFI file the firmware starts directly (no bootloader). No console=ttyS0: the laptop has no serial port, and with
# it the passphrase prompt also tried the missing port ("Failed to query password: Input/output error").
# tpm2-device=auto: without it the initramfs never tries the TPM2+PIN token and only asks for a passphrase
# (first enrollment test, log.md). If the TPM unlock fails, it still falls back to the passphrase.
step_uki() {
  cat > /etc/kernel/cmdline << EOF
rd.luks.name=$ROOT_LUKS_UUID=autark rd.luks.options=$ROOT_LUKS_UUID=tpm2-device=auto root=/dev/mapper/autark rw
EOF
  install -d /boot/efi/EFI/Linux /boot/efi/EFI/BOOT
  local new=/boot/efi/EFI/Linux/autark.efi.new
  rm -f "$new"
  # Built to a temporary name first: the current image is only rotated to "previous" once the new one exists,
  # so a failed build never leaves the boot entry pointing at nothing.
  ukify build --linux=/boot/vmlinuz-$KVER-autark   \
              --initrd=/boot/microcode.img         \
              --initrd=/boot/initramfs-$KVER.img   \
              --cmdline=@/etc/kernel/cmdline       \
              --os-release=@/etc/os-release        \
              --uname=$KVER                        \
              --signtool=systemd-sbsign            \
              --no-sign-kernel                     \
              --secureboot-private-key=$SB/db.key  \
              --secureboot-certificate=$SB/db.crt  \
              --output="$new"
  [ -s "$new" ]
  [ -e /boot/efi/EFI/Linux/autark.efi ] && mv -v /boot/efi/EFI/Linux/autark.efi /boot/efi/EFI/Linux/autark-previous.efi
  mv -v "$new" /boot/efi/EFI/Linux/autark.efi
  # The path firmware tries when it has no boot entries. Under Secure Boot the bare image is refused (the firmware
  # isn't given Autark's key), so once shim is installed the fallback is shim + image too, the standard layout.
  if [ -e /boot/efi/EFI/autark/shimx64.efi ]; then
    cp -v /boot/efi/EFI/autark/shimx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI
    cp -v /boot/efi/EFI/autark/mmx64.efi   /boot/efi/EFI/BOOT/mmx64.efi
    cp -v /boot/efi/EFI/Linux/autark.efi   /boot/efi/EFI/BOOT/grubx64.efi
  else
    cp -v /boot/efi/EFI/Linux/autark.efi /boot/efi/EFI/BOOT/BOOTX64.EFI
  fi
  # On the laptop the firmware can't add a key to db, so Autark boots through Ubuntu's Microsoft-signed shim, which
  # checks the image against Autark's key in the MOK list (log.md, Step 7b). shim always loads "grubx64.efi" from its
  # own folder: the current image goes in EFI/autark/, the previous one in EFI/autark-prev/.
  if [ -e /boot/efi/EFI/autark/shimx64.efi ]; then
    cp -v /boot/efi/EFI/Linux/autark.efi /boot/efi/EFI/autark/grubx64.efi
    [ -e /boot/efi/EFI/Linux/autark-previous.efi ] && cp -v /boot/efi/EFI/Linux/autark-previous.efi /boot/efi/EFI/autark-prev/grubx64.efi
  fi
  ukify inspect /boot/efi/EFI/Linux/autark.efi | grep -E '^\.(linux|initrd|cmdline|osrel|uname)|size'
}

run_pkg cpio      cpio-2.15.tar.bz2  pkg_cpio
run_pkg firmware  -                  step_firmware
run_pkg microcode -                  step_microcode
run_pkg dracut    dracut-112.tar.gz  pkg_dracut
run_pkg initramfs -                  step_initramfs
run_pkg sb-key    -                  step_secureboot_key
run_pkg uki       -                  step_uki
echo "== boot image done: /boot/efi/EFI/Linux/autark.efi"
