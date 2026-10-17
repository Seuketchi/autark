#!/bin/bash
# Unlock Autark's root READ-ONLY at /mnt/autark-ro (e.g. to read its journal from Ubuntu). Your passphrase goes
# straight to cryptsetup. Close again with: sudo umount /mnt/autark-ro && sudo cryptsetup close autark-ro
D=/dev/nvme0n1p7
[ "$(lsblk -no PARTLABEL $D)" = autark-a ] || { echo "$D is not autark-a - stopping"; read -r _; exit 1; }
echo "== Autark disk passphrase (opens root read-only; nothing is written)"
until sudo cryptsetup open --readonly $D autark-ro; do echo "Didn't open, try again."; done
sudo mkdir -p /mnt/autark-ro && sudo mount -o ro /dev/mapper/autark-ro /mnt/autark-ro && echo "Opened read-only. Tell Claude 'open'. You can close this window."
read -r -p "Press Enter to close." _
