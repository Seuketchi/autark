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
- ~~LFS 13.1 has no libstdc++ in chapter 5~~ WRONG, see the rebuild below: my page listing missed it.

## 2026-10-16 — Chapters 5–6 rebuilt from scratch

What went wrong, in order:
1. **Missed two book pages.** I listed each chapter's pages with a regex allowing only `[a-z0-9-]`, which silently
   dropped `gcc-libstdc++.html` (chapter 5) and `Python.html` (chapter 7). Without libstdc++, chapter 6's ncurses
   (C++ binding) and GCC pass 2 failed: `fatal error: exception: No such file or directory`.
2. **Failures weren't caught.** Each package ran as `if ! ( set -e; pkg ); then`, but bash ignores errexit for
   everything inside a condition, subshells included. A failed `make` carried on; GCC pass 2's last command
   (`ln -sv gcc cc`) succeeded, so it reported "done in 26s" and `/usr/bin/gcc` was missing.
3. Earlier in chapter 6: build functions named after commands (`make`, `tar`…) shadowed them and recursed into a
   segfault; and `tar -tf | head -1` died of SIGPIPE under pipefail, exiting silently. Neither touched `$LFS`.

Since failed builds still ran their install steps, `$LFS` held partial installs. Wiped `usr etc var tools lib64`
(sources kept) and rebuilt chapters 5 and 6 with:
- `scripts/lfs/build-lib.sh`: one shared build helper; runs the package subshell as a plain command so errexit
  works; tested with a deliberately failing package (stops at the failing line, script exits 1).
- chapter 5 now includes `gcc-libstdc++`; chapter 7 now includes Python.
- Checks: after each chapter, scan every log for `make: ***` and `configure: error`, and check key binaries exist.
- Rebuild result: chapter 5 (incl. libstdc++ 71 s) and chapter 6 (17 packages; GCC pass 2 599 s) all done.
  Log scan for `make: ***` / `configure: error` / `fatal error`: zero hits in every log.
  Present in `$LFS/usr/bin`: gcc g++ cc ld as make bash sh tar xz sed gawk grep file patch m4; libstdc++ and libncursesw installed.

## 2026-10-16 — Step 4 (chapter 7, chroot)

- `sudo LFS=/mnt/lfs bash scripts/lfs/ch7-chroot.sh`: chown to root, kernfs mounts, chroot, inside phases, unmount.
- dirs, files, gettext 278 s, bison 35 s, perl, zlib 2 s (checked: libz.so 1.3.2 + zlib.h installed, libz.a removed),
  mpdecimal 8 s, Python 75 s, texinfo 62 s, util-linux 39 s, cleanup (`/tools` removed). Log scan: zero errors.
- After exit only the image's own mounts remain (kernfs unmounted by the trap).
- Chroot clock reads UTC (no timezone yet).
- **Checkpoint:** `backup-ch7.tar.xz`, 1.2 GB, 20,690 entries, `xz -t` OK (git-ignored, in the repo folder).
  Restore: wipe `$LFS` except `sources/`, then `tar -xpf backup-ch7.tar.xz -C $LFS` as root.

## 2026-10-17 — Step 5 (chapter 8) setup

- `scripts/lfs/ch8-inside.sh`, generated from the book (`scripts/lfs/ch8-gen/`). 81 packages; GRUB left out
  (Autark has no bootloader). 25 blocks skipped: optional docs, upgrade-only (nscd), alternatives
  (install-locales), interactive (`tzselect`, `passwd root`, `vim -c ':options'`, `exec bash --login`).
- Replacements: timezone Asia/Manila; groff paper `letter` (change via /etc/papersize); libffi
  `--with-gcc-arch=x86-64-v3` instead of `native` (decisions.md CPU target); glibc gets `en_PH.UTF-8`
  and `--enable-fortify-source=3`.
- Flags from here on (your decision, 2026-10-17): CFLAGS/CXXFLAGS `-O2 -march=x86-64-v3 -pipe
  -fstack-protector-strong -fstack-clash-protection -fcf-protection=full -D_FORTIFY_SOURCE=3`,
  LDFLAGS `-Wl,-O1 -Wl,-z,relro -Wl,-z,now`. glibc: no FORTIFY in CFLAGS, no LDFLAGS (it refuses / links ld.so itself).
  Known gaps: bzip2 hard-codes its flags; GMP tunes to the build CPU (book default, not x86-64-v3).
  Verify coverage after the build by scanning binaries for stack protector, FORTIFY and BIND_NOW.
- Tracking (your decision): before/after snapshot per package → `/var/lib/autark/files/<package>`.
- Tests: logged, not fatal (`/sources/logs/test-failures.txt`), except GMP (≥199 PASS) and MPFR (FAIL 0).
- Root has no password yet (`passwd root` skipped; locked until you set it, before the first boot).

**Open for Steps 6–7 (found reading chapter 8):**
- [ ] The book builds systemd with `-D ukify=disabled` (needs the Python `pefile` module). Step 6 uses `ukify`
  to build the signed boot image: build pefile (BLFS) and rebuild, or run the host's ukify.
- [ ] The book's systemd has no `systemd-cryptsetup` / `systemd-cryptenroll`: no libcryptsetup or tpm2-tss.
  Autark's boot needs both (LUKS unlock, TPM+PIN enroll). Build cryptsetup (+ its deps) and tpm2-tss from
  BLFS, then rebuild systemd with them, before Step 6's initramfs.

## 2026-10-17 — Step 5: glibc

- First try failed at `make`, before install: with `-fcf-protection=full` in CFLAGS but no `--enable-cet`,
  ld.so links without `_dl_cet_open_check`/`_dl_cet_check`/`_dl_cet_setup_features`. Fix: glibc's CFLAGS drop
  `-fcf-protection`, configure gets `--enable-cet` (rule in `ch8-gen/gen.py`).
- Also: background commands run under zsh, so `${PIPESTATUS[0]}` was empty. Exit codes are now read without a pipe.
- glibc-2.44: 976 s. Tests: 6815 PASS, **1 FAIL (io/tst-lchmod, the book's first known failure)**, 16 XFAIL,
  582 UNSUPPORTED, 0 timed out.
- Checked: libc.so.6 carries `x86 feature: IBT, SHSTK`; `/etc/localtime` → Asia/Manila; 1861 files tracked.
