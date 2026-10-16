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
- [x] The book builds systemd with `-D ukify=disabled` (needs the Python `pefile` module). Step 6 uses `ukify`
  to build the signed boot image: build pefile (BLFS) and rebuild, or run the host's ukify.
- [x] The book's systemd has no `systemd-cryptsetup` / `systemd-cryptenroll`: no libcryptsetup or tpm2-tss.
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
- binutils: 1 FAIL (`tmpdir/gp-gmon`; book: "one test related to gprofng is known to fail"). acl: 1 FAIL
  (`test/cp.run`; book: known until coreutils has ACL support).
- GCC 16.2.0: 4789 s with tests. Compared with the reference LFS 13.1 build log (i7-14700K, test-logs/830-gcc-16.2.0):
  unexpected failures gcc 80 = 80, g++ 66 = 66; every reference FAIL also fails here. Extra: libstdc++ 82
  (reference 0), all libstdc++ tests (`*/nonnull.cc`, `*/overwrite.cc`, `*/default_init.cc`…).
  Likely cause: libstdc++'s testsuite reuses the build's CXXFLAGS (`-D_FORTIFY_SOURCE=3 -fstack-protector-strong…`,
  visible in the log), which changes warning/memory-content tests. **Not verified per test** (build dir deleted).
  - [ ] After chapter 8: re-run a few of those libstdc++ tests without the hardening flags to confirm.

## 2026-10-17 — Step 5 done (chapter 8)

- 81/81 packages, exit 0. Per-package file lists in `/var/lib/autark/files/` (Autark root).
- Test failures, each checked:
  | Package | Failed | Verdict |
  |---|---|---|
  | glibc | io/tst-lchmod | book: known in chroot |
  | binutils | tmpdir/gp-gmon | book: gprofng test known |
  | acl | test/cp.run | book: known until coreutils has ACL |
  | GCC | gcc 80, g++ 66 | **identical** to reference LFS 13.1 build log |
  | GCC | libstdc++ 82 extra | likely our CXXFLAGS in its testsuite — not verified |
  | libelf | 9 (reference: 0) | likely: our CFLAGS replace autoconf's `-g -O2`, so the "-self" DWARF tests have no DWARF — not verified |
  | Python | test_urllib2, test_urllibnet | book: known (no DNS) |
  | findutils | test-regex-el | book: known |
  | groff | neqn-smoke-test.sh | book: known |
  | tar | capabilities: binary store/restore | book: known (no selinux) |
  | vim | log lacks "FAILED: 0" | **unverified**: vim-test.log was deleted with the build dir |
  | systemd | core - systemd:test-namespace (1/1862) | book: known in chroot |
  | e2fsprogs | m_assume_storage_prezeroed (1/394) | book: known |
- Hardening scan (`scripts/lfs/hardening-scan.sh /mnt/lfs`, 1260 ELF files): PIE 100%, RELRO 100%, CET 94%,
  BIND_NOW 69%. Gaps: glibc's own tools (no LDFLAGS by design), **Perl and everything built through it**
  (Perl's Configure ignores CFLAGS/LDFLAGS), bzip2 (hard-coded flags). A Perl process runs without IBT,
  because IBT needs every loaded object marked.
- Image file had grown to 27 GB (deleted build files never released). Enabled discards on both LUKS volumes
  (`cryptsetup refresh --allow-discards`) and ran `fstrim`: 27 GB → 3.1 GB, Ubuntu back to 80 GB free.
  Trade-off: discards reveal which blocks are used (not their contents). Re-run fstrim after big builds.
- **Checkpoint:** `backup-ch8.tar.xz`, 895 MB, 52,571 entries, `xz -t` OK.

Open after chapter 8:
- [ ] Rebuild Perl with `-Dccflags`/`-Dlddlflags` carrying Autark's flags; rebuild bzip2 with them too.
- [ ] Keep `-g` out of shipped binaries but confirm the libelf and libstdc++ test theories once (rebuild with `-g`
      / without hardening flags, re-run just those tests).
- [ ] Build failures should keep the source dir's test logs: copy `*.log`/`*.sum` to `/sources/logs/<pkg>/` before deleting.

## 2026-10-17 — Disk encryption and TPM support (before Step 6)

Script: `scripts/lfs/blfs-crypto-inside.sh` (BLFS 13.1-systemd commands; `[Autark]` marks deviations).
Sources, each verified:
- BLFS md5 match: LVM2-2.03.42, popt-1.19, cmake-4.4.2, json-c-0.19, cryptsetup-2.8.7.
- libaio-0.3.113: BLFS URL (releases.pagure.org) 404s; Debian's `libaio_0.3.113.orig.tar.gz` has the **identical
  md5** BLFS lists.
- tpm2-tss-4.2.0 (not in BLFS): GitHub release + `.asc`. Good signature by key D533275B…8F4F9A45D7FFEE74
  (Andreas Fuchs, Infineon), fetched from keys.openpgp.org; GitHub lists the same key on `AndreasFuchsTPM`, who
  commits to tpm2-tss (the project's RELEASE.md rule). sha256 b53f0c5c8c4ce17f05701a410ca9688f725ca380c9bc4640eacd0eadb1fea124.
- pefile-2024.8.26 (not in BLFS): PyPI sdist, sha256 matches PyPI's 3ff6c5d8b43e8c37bb6e6dd5085658d658a7a0bdcd20b6a07b1fcfc1c4e9d632.
Deviations: CMake `--no-system-libs` (no curl/libarchive/libuv/nghttp2); LVM2 and cryptsetup tests skipped
(they drive the host kernel's device-mapper, which holds Autark's own volumes); tpm2-tss `--disable-fapi`;
`tss` user/group created by hand (sysusers=false); systemd rebuilt with `ukify`, `libcryptsetup`, `tpm2` enabled.
- [ ] Step 6 kernel needs (cryptsetup page): BLK_DEV_DM, DM_CRYPT, CRYPTO_AES, CRYPTO_XTS, CRYPTO_SHA256,
  CRYPTO_USER_API_SKCIPHER; plus TPM: TCG_TPM, TCG_TIS / TCG_CRB (from hardware/target).
- Built (exit 0, no test failures): libaio 1 s, LVM2 23 s, popt 12 s, CMake 337 s, json-c 9 s, cryptsetup 16 s,
  tpm2-tss 32 s, pefile 1 s, systemd rebuild 71 s. All tracked in /var/lib/autark/files/.
- Verified inside the chroot: `systemctl --version` shows `+LIBCRYPTSETUP +TPM2 +OPENSSL`;
  `systemd-cryptsetup`, `systemd-cryptenroll`, `ukify` (261.2) run; `cryptsetup 2.8.7`; `import pefile` works;
  group `tss` (998). Both Step 6 blockers (ukify, cryptsetup/TPM in systemd) are closed.

## 2026-10-17 — Step 6 (configure, kernel, boot image)

Config (`scripts/lfs/ch9-config-inside.sh`): hostname `autark`; os-release NAME="Autark" ID=autark; networkd DHCP on
any wired link (Wi-Fi with Step 8); resolved DNS-over-TLS to Quad9, no plain fallback; RTC in UTC like the host
(LocalRTC=no); keymap us; LANG=en_US.UTF-8; book's profile/inputrc/shells; fstab by mapper names + ESP UUID;
crypttab for /home with `/etc/cryptsetup-keys.d/autark-home.key` (0400, enrolled from the host and tested); zram
service calling `/usr/lib/autark/zram-swap` (logic in a script: systemd expands `$VAR` inside ExecStart= itself).

Kernel 7.1.8 (`scripts/lfs/ch10-kernel-inside.sh`): Ubuntu's config for this laptop → localmodconfig → required
options → checked. 15 MB + 279 signed modules; key in `/root/kernel-keys/` (0600). The check caught, before compiling:
- `KEXEC_FILE` forced back on by `KEXEC_HANDOVER` (select overrides disable) → also off: KEXEC_HANDOVER, CRASH_DUMP.
- USB-net/Type-C drivers dropped: localmodconfig switched off their menus → `USB_NET_DRIVERS`, `TYPEC` added.
- `DEBUG_INFO_NONE` didn't win its choice → other DWARF members turned off.
Compile fixes: `GENDWARFKSYMS` off (needs libdw's dwarf.h). `yes '' | make localmodconfig` died of SIGPIPE under
pipefail → `(yes '' || true) | …`.
Hardware note: the NVMe sits behind Intel VMD, so `CONFIG_VMD=y` is what makes the root disk visible at all.

Sources (all verified): linux-firmware-20260916 (kernel.org autosigner signature, key from kernel.org's pgpkeys git,
sha256 f80dcb75…); Intel microcode-20260925 (unsigned tarball; the CPU only accepts Intel-signed microcode);
cpio-2.15 (BLFS md5); dracut-ng 112 (GPG sig by Neal Gompa, key C5EC6EF7E1EA6B86 on release author `Conan-Kudo`'s
GitHub); pyelftools-0.33 (PyPI sha256).

Boot (`scripts/lfs/step6-boot-inside.sh`): this laptop's firmware only (graphics, Wi-Fi + WHENCE links, Bluetooth,
Realtek NIC); microcode `06-ba-02` as an early cpio; dracut, not host-only (a chroot would detect the build loop
device); `autark.efi` 34 MB = systemd-stub + kernel + initramfs (18.7 MB) + cmdline + osrel + SBAT, copied to
`EFI/BOOT/BOOTX64.EFI`. Initramfs checked: systemd-cryptsetup(+generator), libcryptsetup, libtss2 esys/mu/rc/tcti-device.
Fixes on the way, each failing at configure, before install:
- dracut's journald module needs `systemd-sysusers` → systemd rebuilt with `sysusers=true`.
- dracut's tpm2-tss module needs the tpm2-tools CLI → dropped; systemd dlopens the TSS libs, so they're `install_items`.
  **Assumption until Step 7b proves it on the real TPM.**
- ukify needs systemd-stub → systemd rebuilt with `bootloader=enabled` (needs pyelftools) and SBAT naming Autark.
Cmdline: `rd.luks.name=33727520-…=autark root=/dev/mapper/autark rw console=tty0 console=ttyS0,115200`.

Open before Step 7b:
- [ ] **Signing**: the image is UNSIGNED. `sbctl` is Go (no Go here); pick sbsigntools (C) or sign from the host.
- [ ] SOF audio firmware isn't in linux-firmware (sof-bin project).
- [ ] Firewall (decisions.md: nftables, block incoming) — nothing listens yet.
- [ ] Lockdown=integrity disables hibernation; decisions.md mentions an optional hibernate swap file. Your call.
- [ ] The kernel's version string says root@Seukechi (chroot borrows the host name). Cosmetic.
