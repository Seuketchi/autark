#!/usr/bin/env bash
# Undo the temporary changes made to the Ubuntu host while building Autark.
# Idempotent: every item checks the current state first and skips if already done.
# Anything that deletes data asks first and defaults to No. Run it yourself, as your normal user:
#   bash scripts/host-cleanup.sh
#
# Items, in run order (log.md section in brackets):
#   1. lfs build user + /home/lfs ............ [2026-10-16 Step 2]   asks (deletes home)
#   2. /etc/bash.bashrc restored from .NOUSE . [2026-10-16 Step 2; build-guide 7b.9]
#   3. /bin/sh diversion (bash -> dash) ...... [2026-10-16 Step 0]    uses the undo command recorded there
#   4. autark.img (the 97 GB build image) .... [2026-10-16 Step 1; build-guide 7b.9]   asks
#   5. backup-ch7/ch8.tar.xz in the repo ..... [2026-10-16 Step 4, 2026-10-17 Step 5]  asks
#   6. qemu test files: ovmf-vars.fd, ovmf-vars-sb.fd, qemu-boot.log
#                                            [2026-10-17 Step 7a, Signing]           asks
#   7. autark-db.der in the repo ............. [2026-10-17 Signing]   asks (a copy lives on Autark's ESP)
#   8. /mnt/lfs mount-point directory ........ [2026-10-16 Step 1]    only if empty and unmounted (rmdir)
#   9. Passwordless sudo rule /etc/sudoers.d/autark-build ... [2026-10-16 Step 1]  LAST, then `visudo -c`
#
# Printed, not done (optional): the `sudo apt remove` line for the build packages
#   [2026-10-16 Step 0: bison gawk m4 texinfo cryptsetup qemu-system-x86 ovmf; 2026-10-17 Signing: python3-virt-firmware].
#
# NOT done by this script:
#   - Autark's partitions /dev/nvme0n1p6-p9, or anything mounted under /mnt/lfs (that is the real Autark now).
#   - The Ventoy USB backup (autark-backup-2026-10-17/).
#   - Timeshift snapshots (the kept "initial baseline", the schedule setting).
#   - MOK keys (mokutil) and Secure Boot settings; the host's own shim/MOK entries.
#   - Firmware boot entries (efibootmgr), including the stray Boot0004 "UEFI OS".
#   - The git repo itself, or /etc/sudoers (only the one drop-in file is removed).
#   - openvpn-dco-dkms / the failed 7.0.0-38 kernel update (your call, log.md 2026-10-17 Signing).
#   - efibootmgr (a Step 7b tool you may still want) and the apt packages above.
#   - /root/autark-build.key (already shredded, log.md Step 7b) and the Autark image's own files.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUDOERS_RULE=/etc/sudoers.d/autark-build

say()  { printf '\n==> %s\n' "$*"; }
skip() { printf '    skip: %s\n' "$*"; }
ok()   { printf '    ok: %s\n' "$*"; }
warn() { printf '    WARNING: %s\n' "$*" >&2; }
ask()  { local a; read -r -p "    $1 [y/N] " a; [[ "$a" =~ ^[Yy]([Ee][Ss])?$ ]]; }

if [ "$(id -u)" -eq 0 ]; then
  echo "Run as your normal user, not root: the script calls sudo itself." >&2
  exit 1
fi
sudo -n true 2>/dev/null || warn "passwordless sudo is already gone; you will be asked for your password."

# Guard: the real Autark may be open on this host right now. This script never unmounts it.
if mountpoint -q /mnt/lfs 2>/dev/null; then
  warn "/mnt/lfs is mounted (Autark is open on the host). Left alone; unmount it yourself when you are done with it."
fi

remove_lfs_user() {
  say "Remove the 'lfs' build user and its home (it only built the toolchain; its files in Autark belong to root)."
  if ! getent passwd lfs >/dev/null; then skip "user lfs does not exist"; return; fi
  if pgrep -u lfs >/dev/null; then warn "lfs still has running processes; not removing it"; return; fi
  if ask "Delete user lfs AND /home/lfs?"; then
    sudo userdel -r lfs || true      # userdel -r exits 12 if the mail spool is missing; verify below instead
    if getent passwd lfs >/dev/null || [ -e /home/lfs ]; then warn "lfs user or /home/lfs still present"; else ok "lfs user and /home/lfs gone"; fi
  else
    skip "kept"
  fi
}

restore_bashrc() {
  say "Put /etc/bash.bashrc back (it was moved aside to .NOUSE so the book's clean-environment shell works)."
  if [ -e /etc/bash.bashrc ] && [ ! -e /etc/bash.bashrc.NOUSE ]; then skip "/etc/bash.bashrc already in place"; return; fi
  if [ ! -e /etc/bash.bashrc.NOUSE ]; then warn "neither file exists; reinstall with: sudo apt install --reinstall bash"; return; fi
  if [ -e /etc/bash.bashrc ]; then
    warn "both exist; not overwriting. Compare: diff /etc/bash.bashrc /etc/bash.bashrc.NOUSE"; return
  fi
  sudo mv -- /etc/bash.bashrc.NOUSE /etc/bash.bashrc
  if [ -f /etc/bash.bashrc ] && [ ! -e /etc/bash.bashrc.NOUSE ]; then ok "/etc/bash.bashrc restored"; else warn "restore failed"; fi
}

restore_dash() {
  say "Give /bin/sh back to dash (undo the local dpkg diversion that pointed /usr/bin/sh at bash)."
  if ! dpkg-divert --list /usr/bin/sh | grep -q 'local diversion of /usr/bin/sh'; then
    skip "no local diversion of /usr/bin/sh"
  else
    if [ ! -L /usr/bin/sh ] || [ "$(readlink /usr/bin/sh)" != bash ]; then
      warn "/usr/bin/sh is not the symlink to bash that the log describes; not touching it"; return
    fi
    # Exact undo from log.md (Step 0), in one root shell so a failed rm stops before the divert is dropped.
    sudo bash -c 'rm /usr/bin/sh && dpkg-divert --remove --rename /usr/bin/sh'
  fi
  local got; got="$(readlink -f /bin/sh)"
  if [ "$got" = /usr/bin/dash ]; then ok "readlink -f /bin/sh -> $got"; else warn "/bin/sh resolves to $got, expected /usr/bin/dash"; fi
}

# Refuse to delete autark.img if anything still holds it open.
image_in_use() {
  [ -n "$(losetup -j "$REPO/autark.img" 2>/dev/null)" ] && return 0
  pgrep -f 'qemu-system.*autark\.img' >/dev/null && return 0
  return 1
}

remove_image() {
  say "Delete the build image autark.img (Autark now runs from its own partitions; the guide says wait a week of real use)."
  local f="$REPO/autark.img"
  if [ ! -e "$f" ]; then skip "autark.img already gone"; return; fi
  if image_in_use; then warn "autark.img is attached to a loop device or used by qemu; release it first"; return; fi
  if ask "Delete $(du -h --apparent-size "$f" | cut -f1) $f (rebuildable from the ch8 backup + scripts, not from anywhere else)?"; then
    rm -f -- "$f"
    [ ! -e "$f" ] && ok "autark.img gone" || warn "autark.img still present"
  else skip "kept"; fi
}

remove_backups() {
  say "Delete the build checkpoints backup-ch7.tar.xz / backup-ch8.tar.xz (the ch8 copy is also on the Ventoy stick)."
  local f found=0
  for f in "$REPO/backup-ch7.tar.xz" "$REPO/backup-ch8.tar.xz"; do
    [ -e "$f" ] || continue
    found=1
    if ask "Delete $f ($(du -h "$f" | cut -f1))?"; then
      rm -f -- "$f"
      [ ! -e "$f" ] && ok "$(basename "$f") gone" || warn "$f still present"
    else skip "kept $(basename "$f")"; fi
  done
  [ "$found" -eq 1 ] || skip "no backup tarballs left"
}

remove_qemu_files() {
  say "Delete the qemu test leftovers (OVMF variable copies and the boot recording; qemu-boot.sh recreates them)."
  local f found=0
  for f in "$REPO/ovmf-vars.fd" "$REPO/ovmf-vars-sb.fd" "$REPO/qemu-boot.log"; do
    [ -e "$f" ] || continue
    found=1
    if ask "Delete $f?"; then
      rm -f -- "$f"
      [ ! -e "$f" ] && ok "$(basename "$f") gone" || warn "$f still present"
    else skip "kept $(basename "$f")"; fi
  done
  [ "$found" -eq 1 ] || skip "no qemu files left"
}

remove_cert() {
  say "Delete the repo copy of Autark's public Secure Boot cert (a copy stays on Autark's ESP at EFI/autark/autark-db.der)."
  local f="$REPO/autark-db.der"
  if [ ! -e "$f" ]; then skip "already gone"; return; fi
  if ask "Delete $f?"; then
    rm -f -- "$f"
    [ ! -e "$f" ] && ok "autark-db.der gone" || warn "still present"
  else skip "kept"; fi
}

remove_mountpoint() {
  say "Remove the empty /mnt/lfs mount-point directory (plain rmdir: it fails, harmlessly, if anything is inside)."
  if [ ! -d /mnt/lfs ]; then skip "/mnt/lfs does not exist"; return; fi
  if mountpoint -q /mnt/lfs; then skip "/mnt/lfs is mounted"; return; fi
  if sudo rmdir /mnt/lfs 2>/dev/null; then ok "/mnt/lfs removed"; else skip "/mnt/lfs not empty; left alone"; fi
}

# MUST be last: every step above uses sudo.
remove_sudo_rule() {
  say "Remove the passwordless-sudo rule $SUDOERS_RULE (last step; after this sudo asks for your password again)."
  if [ ! -e "$SUDOERS_RULE" ] && ! sudo -n test -e "$SUDOERS_RULE" 2>/dev/null; then skip "rule already gone"; return; fi
  sudo rm -f -- "$SUDOERS_RULE"
  sudo -k                                   # drop any cached credentials so the check below is honest
  echo "    Checking sudoers syntax (you will be asked for your password now)."
  if sudo visudo -c; then ok "visudo -c passed"; else warn "visudo -c reported a problem; inspect /etc/sudoers.d/ before closing this terminal"; fi
  sudo -k
  if sudo -n true 2>/dev/null; then warn "passwordless sudo still works; another rule grants it"; else ok "sudo -n true now fails, as intended"; fi
  if sudo -n test -e "$SUDOERS_RULE" 2>/dev/null; then warn "$SUDOERS_RULE still exists"; fi
}

print_optional_packages() {
  say "Optional, not run: the packages installed for the build."
  echo "    qemu-system-x86, ovmf and python3-virt-firmware are still useful for testing new kernels/images (build guide 7);"
  echo "    cryptsetup is also handy for opening Autark's volumes from Ubuntu. Remove only what you won't use:"
  echo "      sudo apt remove bison gawk m4 texinfo cryptsetup qemu-system-x86 ovmf python3-virt-firmware && sudo apt autoremove"
}

remove_lfs_user
restore_bashrc
restore_dash
remove_image
remove_backups
remove_qemu_files
remove_cert
remove_mountpoint
print_optional_packages
remove_sudo_rule

say "Done. Re-run any time; finished items are skipped."
