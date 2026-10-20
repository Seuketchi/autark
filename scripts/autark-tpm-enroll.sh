#!/bin/bash
# autark-tpm-enroll: let the TPM unlock the encrypted root, behind a PIN, after Secure Boot is on. Run it once on the
# first boot of an installed Autark (autark-install prints this step); needs root and a TTY, because
# systemd-cryptenroll asks for the disk passphrase and the new PIN.
#
#   sudo autark-tpm-enroll [--replace] [--force] [--dry-run]
#
# It binds the root volume to PCR 7 (the Secure Boot state, so a changed key or a disabled Secure Boot stops the TPM
# from unlocking), prints a recovery key once (write it down: it is the way in if the TPM or the PIN is lost), adds
# tpm2-device=auto to /etc/kernel/cmdline, and rebuilds the boot image. --replace removes an earlier TPM slot first.
# --force enrols even with Secure Boot off (the binding then breaks the day Secure Boot is turned on).
set -euo pipefail

CMDLINE=${CMDLINE:-/etc/kernel/cmdline}
REPLACE=0 FORCE=0 DRY=0
die() { echo "autark-tpm-enroll: $*" >&2; exit 1; }
run() { if [ "$DRY" = 1 ]; then printf '  + %s\n' "$*"; else "$@"; fi; }
while [ $# -gt 0 ]; do
  case $1 in
    --replace) REPLACE=1 ;; --force) FORCE=1 ;; --dry-run|-n) DRY=1 ;;
    -h|--help) sed -n '2,/^set -e/p' "$0" | sed '$d;s/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done
[ "$DRY" = 1 ] || [ "$(id -u)" = 0 ] || die "needs root"
[ -s "$CMDLINE" ] || die "no $CMDLINE"
[ -e /dev/tpmrm0 ] || [ "$DRY" = 1 ] || die "no TPM 2.0 (/dev/tpmrm0): the disk keeps unlocking with the passphrase"

# The root volume: rd.luks.name=<uuid>=autark on the kernel command line.
UUID=$(sed -n 's/.*rd\.luks\.name=\([0-9a-fA-F-]\{36\}\)=.*/\1/p' "$CMDLINE" | head -1)
[ -n "$UUID" ] || die "no rd.luks.name=<uuid>=... in $CMDLINE"
DEV=/dev/disk/by-uuid/$UUID
[ -e "$DEV" ] || [ "$DRY" = 1 ] || die "no $DEV"

# Secure Boot on? The EFI variable's last byte is 1 when it is.
sb=/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c
if [ -r "$sb" ] && [ "$(tail -c1 "$sb" | od -An -tu1 | tr -d ' ')" = 1 ]; then echo "Secure Boot is on."
elif [ "$FORCE" = 1 ]; then echo "Secure Boot is off; enrolling anyway (--force)."
else die "Secure Boot is off. Enrol /EFI/autark/autark-db.der in the firmware's setup, turn Secure Boot on, boot Autark, then run this again (or --force)."; fi

[ "$REPLACE" = 0 ] || run systemd-cryptenroll --wipe-slot=tpm2 "$DEV"
run systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes --recovery-key "$DEV"

# tpm2-device=auto: without it the initramfs only asks for the passphrase and never tries the TPM.
if grep -q "rd.luks.options=$UUID=" "$CMDLINE"; then
  grep -q 'tpm2-device=auto' "$CMDLINE" || run sed -i "s|rd.luks.options=$UUID=|rd.luks.options=$UUID=tpm2-device=auto,|" "$CMDLINE"
else
  run sed -i "s|\$| rd.luks.options=$UUID=tpm2-device=auto|" "$CMDLINE"
fi
run autark-mkuki
echo "Done. Reboot: the disk should ask for the PIN, and the passphrase (or the recovery key) still works."
