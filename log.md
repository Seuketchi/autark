# Autark build log

Every package built, every change made, every error. Enough to repeat the build without Claude.

## 2026-10-16 — Step 0 (target laptop: MSI Cyborg 15 A13UCK)

- Host: Ubuntu 26.04 LTS, kernel 7.0.0-34. LFS book: 13.1-systemd.
- Repo cloned to `~/personal/autark` (build guide says `~/autark`; same repo, different path).
- Hardware profile captured to `hardware/target/` (not yet re-run with all devices plugged in).
  `firmware.txt` has only 6 entries: the kernel log needs `adm` group or sudo to read fully.
- Hardware differs from the reference: i5-13420H (Raptor Lake), 24 GB, Intel UHD + NVIDIA RTX 3050 (hybrid).
- Disk: single 512 GB NVMe. Windows 11 (185 GB) at the front, Ubuntu (290 GB) at the end, 100 MB ESP.
  Partitioning (Step 1) is on hold: the 100 MB ESP can't hold two UKIs, and Step 0's layout would wipe this Ubuntu.
- `version-check.sh` (from chapter 2.2): 20 OK. Errors: bison, gawk, m4, texinfo missing; `/bin/sh` is dash.
- Installed bison, gawk, m4, texinfo, cryptsetup, qemu-system-x86, ovmf.
- `/bin/sh` → bash. On Ubuntu 26.04 (dash 0.5.12) `dpkg-reconfigure dash` no longer works: dash ships
  `/usr/bin/sh` itself and the debconf answer is ignored. Done instead with a local diversion, which survives dash updates:
  `dpkg-divert --local --add --rename --divert /usr/bin/sh.dash /usr/bin/sh && ln -s bash /usr/bin/sh`.
  Undo: `rm /usr/bin/sh && dpkg-divert --remove --rename /usr/bin/sh`.
- No terminal in Claude Code's `!` prompt, so `sudo` can't ask for a password there; `pkexec` (desktop password dialog) works.
- `version-check.sh`: all OK, 12 cores.
- Freed 32 GB of caches (Gradle, pip, Chrome, JetBrains, Dart). Plan changed: build into an image file first,
  test in qemu, shrink Ubuntu and move to a partition only once it boots.

## 2026-10-16 — Step 1 (disk image)

- Temporary sudo rule `/etc/sudoers.d/autark-build` installed via pkexec (validated with `visudo -cf` first). Remove in Step 7.
- `autark.img`: 90 GiB sparse, GPT: p1 ESP 1 GiB (vfat, AUTARK-ESP), p2 root A 40 GiB, p3 root B 40 GiB (empty), p4 /home 9 GiB.
- Root A and /home: LUKS2, unlocked for now by a **random key file `/root/autark-build.key`** (root-only, 0400), no passphrase yet.
  Root A LUKS UUID: 33727520-d460-4861-b27f-bef08d44c11f.
  - [ ] Before 7a: add your passphrase to both (`sudo cryptsetup luksAddKey --key-file /root/autark-build.key /dev/loopNp2`, same for p4).
  - [ ] Before 7b: remove the key-file slot from both (`cryptsetup luksKillSlot`), then `shred -u /root/autark-build.key`.
- Mounted at `/mnt/lfs`, `/mnt/lfs/home`, `/mnt/lfs/boot/efi`. Image uses 367 MB on disk after formatting.
- After a reboot: `LOOP=$(sudo losetup -fP --show ~/personal/autark/autark.img)`, `cryptsetup open --key-file /root/autark-build.key` both, mount again.

## 2026-10-16 — Step 2 (sources and build user)

- Sources: LFS 13.1-systemd `wget-list-systemd` + `md5sums`: 94/94 downloaded and md5 OK, 628 MB in `$LFS/sources`.
- Layout per chapter 4.2 (usr-merge symlinks, `lib64`, `tools`), owned by `lfs`.
- `lfs` user per 4.3, **no password set** (locked; reached only through sudo).
- `.bash_profile` / `.bashrc` per 4.4, with `MAKEFLAGS=-j$(nproc)` (12).
- Host change: `/etc/bash.bashrc` → `/etc/bash.bashrc.NOUSE` (book 4.4). **Restore after the build.**
- `su - lfs -c '…'` hangs: the book's `.bash_profile` execs an interactive bash and `su -` starts a full user session.
  Scripts run as lfs through `scripts/as-lfs.sh` instead (same `env -i` + `.bashrc`, no login).

## 2026-10-16 — Step 3 (cross-toolchain, chapter 5)

- Script: `scripts/lfs/ch5-cross-toolchain.sh` (book commands verbatim), run from a copy in `$LFS/sources`
  because `/home/tan` is 750 and `lfs` can't read the repo. Per-package logs in `$LFS/sources/logs/`.
- binutils-2.47 pass 1: 58 s → **1 SBU = 58 s** on this laptop (12 threads).
- gcc-16.2.0 pass 1: 363 s (6.3 SBU). linux-7.1.8 headers: 2 s. glibc-2.44: 108 s (1.9 SBU).
- Sanity check matches the book: interpreter `/lib64/ld-linux-x86-64.so.2`; Scrt1/crti/crtn from `$LFS/lib`;
  headers from `$LFS/tools` and `$LFS/usr/include`; libc from `$LFS/usr/lib/libc.so.6`.
- LFS 13.1 has no libstdc++ in chapter 5; GCC pass 2 builds it (chapter 6).
