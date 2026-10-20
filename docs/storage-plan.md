# Autark storage plan (written 2026-10-20)

Nothing here has been run. It is the written plan item 20 of `docs/autark-retire-checklist.md` asks for. Every step that deletes or
resizes a partition needs your backups to be off this laptop first.

## Where the disk stands

Disk: 476.9 GiB NVMe. Order on disk (start → end):

| Part | Size | What | Fate |
|---|---|---|---|
| p1 | 100 MiB | ESP shared by Windows and Ubuntu (`\EFI\Microsoft`, `\EFI\ubuntu`) | keep |
| p2 | 16 MiB | Microsoft reserved | keep |
| p3 | 185.3 GiB | Windows (NTFS) | keep for now |
| p4 | 994 MiB | Windows recovery | keep for now |
| p5 | 224.6 GiB | Ubuntu (ext4), mounted read-only at /mnt/ubuntu-ro | **delete** |
| p6 | 1 GiB | AUTARK-ESP, `/boot/efi` | keep, don't touch |
| p7 | 40 GiB | LUKS `autark`, root A, 85% full (5.6 GiB free), unlocked by the TPM | **grow to 55 GiB, later 65** |
| p8 | 15 GiB | root B, reserved and never formatted | **delete** (re-create in the free space when the first A/B upgrade needs it) |
| p9 | 10 GiB | LUKS `autark-home`, `/home`, 93% full (648 MiB free), unlocked by a key file on root | **replace**, then delete |

The problem: Ubuntu's space is *before* p6–p9, and the Autark partitions run to the end of the disk, so neither root nor `/home` can
grow into it. The docs already named the two ways out: "a second encrypted volume there, or moving `/home` into it". This plan
moves `/home` into it, and uses the old root-B space to grow root in place.

## Target layout

| Part | Size | What |
|---|---|---|
| p5 (new) | 160 GiB | new LUKS `/home` (the numbering reuses 5) |
| (unallocated) | ~64.6 GiB | kept for root B, created at the first major upgrade; matches a 65 GiB root |
| p6 | 1 GiB | AUTARK-ESP (unchanged) |
| p7 | 55 GiB, then 65 GiB | root A |
| (p8, p9 gone) | | |

Why 160 GiB: what comes back from Ubuntu is roughly work 31 GB, personal 21 GB, Android SDK/emulators about 30 GB, plus caches and
datasets. If Windows is retired too, p3 and p4 join the free space (a single 410 GiB region), and the home partition can be larger.

## Before anything is deleted (on Autark, now)

1. **Off-laptop copies exist**: `~/backup-from-ubuntu` (has private keys: encrypt it) and the keep list from Downloads/Pictures/Documents.
   Chrome passwords exported or synced. Nothing else in `/mnt/ubuntu-ro` is needed: Viber is already in `/opt/viber`.
2. **Boot order: Autark first, before Ubuntu goes.** It is now `0002 (Ubuntu), 0000, 0001 (Autark), 0003, 0004, 0005`. Ubuntu's boot files
   are on p1 and load GRUB from p5, so with p5 gone the machine would stop at a GRUB prompt every boot.
   ```
   sudo efibootmgr -o 0001,0000,0003,0005,0004
   ```
   Reboot once and check it comes up in Autark. Remove the Ubuntu entry only after p5 is deleted: `sudo efibootmgr -b 0002 -B`.
3. **Recovery passphrase works** on root: `sudo cryptsetup luksDump /dev/nvme0n1p7` shows a passphrase slot besides the TPM one. If the TPM
   ever refuses to unlock, this is the way in. (The same is true for p9.)
4. **p8 is really empty**: `sudo blkid /dev/nvme0n1p8` prints nothing.
5. `sudo umount /mnt/ubuntu-ro`.
6. A USB stick (4 GB or more) with **GParted Live**, written from another computer or with `dd` from Autark. **Keep Secure Boot on** when you
   boot it: turning it off changes what the TPM measures (PCR 7) and root would ask for the recovery passphrase.

## Session 1: GParted Live

Boot the stick (F11 or the laptop's boot menu). Check each partition by **size and file system** before touching it, as device names can
differ in the live system.

1. Delete the **224.6 GiB ext4** partition (Ubuntu, p5). Not the 185.3 GiB NTFS one.
2. Delete the **15 GiB unformatted** partition (p8).
3. Resize/Move the **40 GiB `crypto_LUKS`** partition (p7): drag its right edge over the space p8 left, to 55 GiB. GParted can't see inside
   the encrypted volume, so it only changes the partition; the file system inside is grown from Autark later.
4. In the 224.6 GiB of free space create a **160 GiB** partition, file system "unformatted", and leave the rest (~64.6 GiB) unallocated.
5. Apply, wait for it to finish (don't power off), and reboot into Autark.

Expect `lsblk` to show p5 at 160 GiB, p6, p7 at 55 GiB, p9 unchanged.

## Session 1 follow-up, on Autark

Grow root online (no unmount needed):
```
sudo cryptsetup resize autark
sudo resize2fs /dev/mapper/autark
df -h /          # ~55 GiB
```

Make the new `/home` with `scripts/migrate-home.sh`. It needs a quiet system: log out, press Ctrl+Alt+F3, log in as root. Check the
device with `lsblk` first (the new 160 GiB one, normally `/dev/nvme0n1p5`): `prepare` erases it, and refuses one that already has
a file system or encryption on it.
```
~/autark-storage/scripts/migrate-home.sh check /dev/nvme0n1p5     # changes nothing; run it first, while still logged in as you (with sudo)
~/autark-storage/scripts/migrate-home.sh all   /dev/nvme0n1p5     # prepare, copy, verify, switch; asks you to type the device name
```
What `all` does, which you can also run one step at a time (`prepare`, `copy`, `switch`):

1. LUKS2-formats the partition with the same key file as the old `/home`, asks you for a recovery passphrase, makes an ext4 file system.
2. Copies `/home` over with `cp -a`, then compares both trees: owner, mode, size, time and link target of every entry, and the SHA-256
   of every file. Any difference stops it before anything is switched.
3. Replaces the UUID on the `autark-home` line of `/etc/crypttab` (the old line stays as a comment, the old file is saved as
   `/etc/crypttab.bak-before-newhome-<time>`). `/etc/fstab` does not change.

Then reboot. Check `df -h /home` shows ~157 GiB and your files are there. `/home` is unlocked after boot by systemd, not in the
initramfs, so no boot image is rebuilt. If `/home` fails to mount, boot to the emergency shell and restore the saved crypttab.

Leave the old p9 untouched for about a week.

## Session 2 (a week later, optional): GParted Live again

1. Delete the old 10 GiB p9.
2. Resize/Move p7 to take the space: 65 GiB.
3. On Autark: `sudo cryptsetup resize autark` and `sudo resize2fs /dev/mapper/autark`.

## Root B

Nothing to do now. The ~64.6 GiB between the new `/home` and AUTARK-ESP is for it; it is created and formatted at the first major
upgrade (`docs/specs/maintenance.md`). Update the disk-layout row in `docs/specs/decisions.md` and item 20 in the retire checklist when this is done.

## Windows

Left alone here. If you retire it later, p3 and p4 merge with the free region; its boot entry (0000) and `\EFI\Microsoft` on p1 go last,
after Autark has booted without them. Retiring it also removes a source of dbx updates that could change PCR 7.

## What can go wrong

- A resize or move interrupted by a power cut can corrupt the partition. Plug in the charger; that is why the backups come first.
- Two partitions have the same size class (p3 NTFS 185 GiB and p5 ext4 224.6 GiB): read the file system column before deleting.
- If `cryptsetup luksFormat` is pointed at the wrong device it destroys it. Re-run `lsblk` first.
- The new partition takes the number 5 in the live system; boot entries and fstab use UUIDs, so nothing else depends on the number.
