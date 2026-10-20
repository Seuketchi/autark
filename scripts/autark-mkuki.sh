#!/bin/bash
# autark-mkuki: build the initramfs and the signed unified kernel image (one EFI file: microcode, initramfs, kernel and
# command line) for an installed kernel, and put it on the ESP. autark-install runs it in the new system; run it again
# after a kernel update or after changing /etc/kernel/cmdline. The same steps as Step 6.5 of the build guide, for any
# machine: the command line, and the keys, belong to the machine.
#
#   autark-mkuki [--kver VERSION] [--no-initramfs]
#
# KVER defaults to the newest kernel in /usr/lib/modules. Settings (environment, for tests): BOOT=/boot, ESP=/boot/efi,
# SB=/etc/autark/secureboot (db.key and db.crt, made here if missing, with db.der for the firmware's setup screen),
# CMDLINE=/etc/kernel/cmdline. The image is signed with the db key; the previous image is kept as autark-previous.efi.
set -euo pipefail

BOOT=${BOOT:-/boot} ESP=${ESP:-/boot/efi} SB=${SB:-/etc/autark/secureboot} CMDLINE=${CMDLINE:-/etc/kernel/cmdline}
MODDIR=${MODDIR:-/usr/lib/modules}
KVER= INITRAMFS=1
die() { echo "autark-mkuki: $*" >&2; exit 1; }
while [ $# -gt 0 ]; do
  case $1 in
    --kver) KVER=${2:?}; shift ;;
    --no-initramfs) INITRAMFS=0 ;;
    -h|--help) sed -n '2,/^set -e/p' "$0" | sed '$d;s/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done
[ -n "$KVER" ] || KVER=$(ls "$MODDIR" | sort -V | tail -1)
[ -n "$KVER" ] || die "no kernel in $MODDIR"
KERNEL=$BOOT/vmlinuz-$KVER-autark
[ -s "$KERNEL" ] || die "no $KERNEL"
[ -s "$CMDLINE" ] || die "no $CMDLINE (autark-install writes it; it names the encrypted root)"
[ -d "$ESP" ] || die "no $ESP (is the ESP mounted?)"

# The Secure Boot db key: made once on this machine, never overwritten (a new one has to be enrolled again).
if [ ! -s "$SB/db.key" ]; then
  install -d -m 0700 "$SB"
  openssl req -new -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
    -subj "/CN=Autark Secure Boot db $(hostname)/" -keyout "$SB/db.key" -out "$SB/db.crt" 2> /dev/null
  chmod 0400 "$SB/db.key"
  echo "made a new Secure Boot db key in $SB"
fi
openssl x509 -in "$SB/db.crt" -outform DER -out "$SB/db.der"

INITRD=$BOOT/initramfs-$KVER.img
if [ "$INITRAMFS" = 1 ]; then
  # Not host-only: it must also work when the machine's hardware changes, and from an installer's chroot.
  dracut --force --no-hostonly --kver "$KVER" "$INITRD"
fi
[ -s "$INITRD" ] || die "no $INITRD"

install -d "$ESP/EFI/Linux" "$ESP/EFI/BOOT" "$ESP/EFI/autark"
new=$ESP/EFI/Linux/autark.efi.new
rm -f "$new"
initrds=(); [ ! -s "$BOOT/microcode.img" ] || initrds+=(--initrd="$BOOT/microcode.img")
ukify build --linux="$KERNEL" "${initrds[@]}" --initrd="$INITRD" \
  --cmdline=@"$CMDLINE" --os-release=@/etc/os-release --uname="$KVER" \
  --signtool=systemd-sbsign --no-sign-kernel \
  --secureboot-private-key="$SB/db.key" --secureboot-certificate="$SB/db.crt" --output="$new"
[ -s "$new" ] || die "ukify made no image"
[ ! -e "$ESP/EFI/Linux/autark.efi" ] || mv -f "$ESP/EFI/Linux/autark.efi" "$ESP/EFI/Linux/autark-previous.efi"
mv -f "$new" "$ESP/EFI/Linux/autark.efi"
# The path firmware tries with no boot entry, and the certificate to enrol, where the setup screen can read it.
cp -f "$ESP/EFI/Linux/autark.efi" "$ESP/EFI/BOOT/BOOTX64.EFI"
cp -f "$SB/db.der" "$ESP/EFI/autark/autark-db.der"
echo "built $ESP/EFI/Linux/autark.efi for $KVER ($(du -h "$ESP/EFI/Linux/autark.efi" | cut -f1))"
