#!/bin/bash
# Create your everyday (non-root) account inside Autark, from Ubuntu, with Autark open read-write at /mnt/lfs
# (open-autark-rw.sh). Your password goes straight to Autark's own passwd. Group `wheel` is for admin rights
# later (sudo-rs); seat access to the screen, input and sound comes from the logind session, not from groups.
set -euo pipefail
LFS=/mnt/lfs
[ "$(findmnt -no SOURCE $LFS 2>/dev/null)" = /dev/mapper/autark ] || { echo "Autark isn't open at $LFS"; read -r _; exit 1; }
mountpoint -q $LFS/home || { echo "Autark's /home isn't mounted"; read -r _; exit 1; }

read -r -p "== Username for Autark [tan]: " u; u=${u:-tan}
[[ $u =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { echo "Use lowercase letters, digits, - or _"; read -r _; exit 1; }
if sudo chroot $LFS /usr/bin/id "$u" > /dev/null 2>&1; then
  echo "   $u already exists in Autark; only setting the password."
else
  sudo chroot $LFS /usr/sbin/useradd -m -G wheel -s /bin/bash "$u"
  echo "   created $u (home /home/$u on Autark's encrypted /home)"
fi

echo "== Password for $u (mix upper and lower case and a number)"
sudo mount --bind /dev $LFS/dev
trap 'sudo umount $LFS/dev' EXIT
until sudo chroot $LFS /usr/bin/passwd "$u"; do echo "Didn't take, try again."; done
sudo chroot $LFS /usr/bin/id "$u"
echo "Done. Tell Claude 'user done'. You can close this window."
read -r -p "Press Enter to close." _
