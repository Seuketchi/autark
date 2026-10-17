#!/bin/bash
# Unlock Autark READ-WRITE at /mnt/lfs (root, /home by its key file, ESP), for rebuilds from Ubuntu with the chroot
# scripts. Your passphrase goes straight to cryptsetup. Close: sudo umount -R /mnt/lfs && sudo cryptsetup close
# autark-home && sudo cryptsetup close autark
set -u
for p in "6 autark-esp" "7 autark-a" "9 autark-home"; do set -- $p
  [ "$(lsblk -no PARTLABEL /dev/nvme0n1p$1)" = "$2" ] || { echo "nvme0n1p$1 is not $2 - stopping"; read -r _; exit 1; }; done
echo "== Autark disk passphrase (opens root read-write)"
until sudo cryptsetup open --allow-discards /dev/nvme0n1p7 autark; do echo "Didn't open, try again."; done
sudo mkdir -p /mnt/lfs && sudo mount /dev/mapper/autark /mnt/lfs
sudo cryptsetup open --allow-discards --key-file /mnt/lfs/etc/cryptsetup-keys.d/autark-home.key /dev/nvme0n1p9 autark-home
sudo mount /dev/mapper/autark-home /mnt/lfs/home && sudo mount /dev/nvme0n1p6 /mnt/lfs/boot/efi
findmnt -R /mnt/lfs -o TARGET,SOURCE
echo "Done. Tell Claude 'open'. You can close this window."
read -r -p "Press Enter to close." _
