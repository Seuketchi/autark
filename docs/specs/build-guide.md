# Autark build guide

Step by step, from an Ubuntu host to a running Autark with your own desktop shell. Decisions behind each step are in [decisions.md](decisions.md).

## Step 0 — Prepare the target laptop

Autark is built on the laptop it will run on, never on the work laptop. This step is done when the target laptop runs an Ubuntu host, its hardware profile is in the repo, and the book's version check prints no errors. Book reference: chapter 2.2, "Host System Requirements".

1. Use the Ubuntu the target laptop already runs; nothing is repartitioned yet. Autark is built into a disk image file (Step 1), boots in qemu first, and moves onto the real disk only once it works (Step 7). The image is sparse, so it only takes the space actually written: keep about 60 GB free for it and the sources. A laptop with no Ubuntu gets one installed normally first.
2. Clone this repo to `~/autark` (if it lives elsewhere, use that path in every command below). Plug in and use every device you own first (dock, external monitor, headset, phone, USB drives, webcam, Bluetooth devices), so their drivers are loaded. Then capture the hardware profile, which becomes the standard the kernel and firmware steps use:

   ```
   bash ~/autark/scripts/capture-hardware.sh target
   ```

   Commit `hardware/target/`. The work laptop's profile stays in `hardware/work-laptop/` as a reference.
3. Install the missing build tools, plus qemu and its UEFI firmware for testing images:

   ```
   sudo apt install bison gawk m4 texinfo cryptsetup efibootmgr qemu-system-x86 ovmf
   ```
4. Make `/bin/sh` point to bash. On Ubuntu 26.04 `dpkg-reconfigure dash` no longer does this: the dash package ships `/usr/bin/sh` itself and ignores the answer. Divert dash's link instead, so dash updates can't put it back, then check that `readlink -f /bin/sh` prints `/usr/bin/bash`:

   ```
   sudo dpkg-divert --local --add --rename --divert /usr/bin/sh.dash /usr/bin/sh && sudo ln -s bash /usr/bin/sh
   ```

   To undo it after the build: `sudo rm /usr/bin/sh && sudo dpkg-divert --remove --rename /usr/bin/sh`.
5. Copy the `version-check.sh` script from chapter 2.2 into `~/autark/` and run `bash ~/autark/version-check.sh`. Every line should say OK.
6. Install Claude Code and sign in with your **personal** Claude account; the company seat stays on the work laptop.
7. Start the build log at `~/autark/log.md`. Write down every package you build, any changes you made, and every error. With it, the build can be repeated without Claude.

Why: LFS builds its first compiler with the host's tools, and the book's scripts use bash-only syntax. A missing tool shows up as a confusing failure an hour into the build.

## Step 1 — Create the encrypted Autark disk image

This step is done when the image's encrypted root A is mounted at `/mnt/lfs`, its encrypted `/home` at `/mnt/lfs/home`, and its own EFI partition at `/mnt/lfs/boot/efi`. Root B is created but left empty for the first major upgrade ([maintenance.md](maintenance.md)). Book reference: chapters 2.4–2.7.

The image is laid out exactly like the real disk will be: the same four partitions, so Step 7 copies them across one by one. LFS only needs *something* mounted at `$LFS`; a loop device (an image file the kernel treats as a disk) works the same as a partition.

1. **You** add the temporary sudo rule, on the target laptop only. It's removed in Step 7:

   ```
   echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/autark-build && sudo visudo -c
   ```
2. Create the image with four partitions. It's sparse: its size is a ceiling, and only written blocks use space on Ubuntu's disk. Root B stays unwritten, so it costs nothing until the first upgrade. There's no swap partition, because zram handles swap.

   ```
   IMG=~/autark/autark.img
   truncate -s 90G $IMG
   parted -s $IMG mklabel gpt \
     mkpart autark-esp fat32 1MiB 1GiB set 1 esp on \
     mkpart autark-a ext4 1GiB 41GiB \
     mkpart autark-b ext4 41GiB 81GiB \
     mkpart autark-home ext4 81GiB 100%
   ```

   The sizes are the ceiling for the real partitions too, so pick them for the disk Autark will move to. 40 GB per root is an estimate, not a measurement: the installed system should stay well under it, and the biggest builds in Step 8 (Firefox, Rust, WebKitGTK) need their room only while compiling, since each package's build folder is deleted once it's installed. Before each of those, check its "Required disk space" in BLFS against `df -h /`. The spec's earlier 80 GB was sized for keeping build folders around.
3. Attach the image as a disk. Its partitions show up as `${LOOP}p1` to `${LOOP}p4`:

   ```
   LOOP=$(sudo losetup -fP --show $IMG)    # e.g. /dev/loop40
   ```
4. Format the EFI partition, then encrypt root A and `/home` with LUKS2 and format them. Root B stays unformatted until the first upgrade.

   ```
   sudo mkfs.vfat -F 32 -n AUTARK-ESP ${LOOP}p1
   sudo cryptsetup luksFormat --type luks2 ${LOOP}p2
   sudo cryptsetup luksFormat --type luks2 ${LOOP}p4
   sudo cryptsetup open ${LOOP}p2 autark
   sudo cryptsetup open ${LOOP}p4 autark-home
   sudo mkfs.ext4 -L autark-a /dev/mapper/autark
   sudo mkfs.ext4 -L autark-home /dev/mapper/autark-home
   ```

   At boot, `/home` unlocks with a key file stored inside the unlocked root (listed in `/etc/crypttab`), so you only enter the PIN once. The LUKS UUIDs travel with the partitions when Step 7 copies them, so the kernel command line and `/etc/crypttab` stay valid on the real disk.
5. Mount it and set `$LFS`, which every later step uses. Autark has its own EFI partition, so nothing touches Ubuntu's or Windows' boot files:

   ```
   export LFS=/mnt/lfs
   sudo mkdir -p $LFS && sudo mount /dev/mapper/autark $LFS
   sudo mkdir -p $LFS/home && sudo mount /dev/mapper/autark-home $LFS/home
   sudo mkdir -p $LFS/boot/efi && sudo mount ${LOOP}p1 $LFS/boot/efi
   ```

Root A and `/home` are unlocked for now by a random key file, `/root/autark-build.key` (root-only, mode 0400), with no passphrase yet; use `--key-file` with the `luksFormat` and `open` commands above. Before the qemu boot (Step 7a) you add your passphrase to root A. In Step 7b you remove the key-file slot from both volumes and shred the file. TPM-plus-PIN unlocking is added in Step 7b, on the real disk.

After a reboot, attach the image again (`LOOP=$(sudo losetup -fP --show $IMG)`), unlock both partitions with `cryptsetup open --key-file /root/autark-build.key`, and run the three mount commands again before continuing.

## Step 2 — Get the sources and set up the build user

This step is done when every source tarball passes its md5 check and you are logged in as the `lfs` user with a clean environment. Book reference: chapters 3–4.

1. Download the systemd edition's package list and checksums from the book, then fetch everything into `$LFS/sources`:

   ```
   sudo mkdir -m 1777 $LFS/sources
   wget --input-file=wget-list-systemd --continue --directory-prefix=$LFS/sources
   (cd $LFS/sources && md5sum -c md5sums)
   ```
2. Create the top-level directory layout (`etc`, `var`, `usr/{bin,lib,sbin}`, `tools`) and the usr-merge symlinks, as in chapter 4.2.
3. Create the unprivileged `lfs` user that owns the build. The toolchain chapters run as `lfs`, so a mistake there can't damage the host.
4. Give `lfs` a clean shell: the book's `.bash_profile` and `.bashrc`, plus `export MAKEFLAGS=-j$(nproc)` to use every CPU thread. Move the host's `/etc/bash.bashrc` aside as the book says (`.NOUSE`); restore it after the build (Step 7b). `su - lfs -c '…'` hangs, because the book's `.bash_profile` starts an interactive bash. Run scripts as `lfs` with `scripts/as-lfs.sh '<commands>'` instead (same `env -i` and `.bashrc`, no login).

Why a separate user: the cross-toolchain must not pick up Ubuntu's libraries or environment variables. A fresh login with an almost-empty environment is the simplest guarantee.

## Step 3 — Build the cross-toolchain

This step is done when a test program compiled with the new toolchain links against `/lib64/ld-linux-x86-64.so.2` inside `$LFS`, not Ubuntu's copy. Book reference: chapter 5. Runs as the `lfs` user.

1. Binutils, pass 1: the assembler and linker, built to target `x86_64-lfs-linux-gnu`. Its build time sets the book's time unit (SBU), and Claude times it to estimate the rest of the build.
2. GCC, pass 1: a C/C++ compiler with no C library yet.
3. Linux API headers: the kernel interface that glibc compiles against.
4. Glibc: the C library, built with the pass-1 compiler. Then run the book's sanity check, and stop if it fails.
5. Libstdc++: the C++ standard library, so that later C++ packages can build. Without it, chapter 6's ncurses and GCC pass 2 fail with `fatal error: exception: No such file or directory`.

The commands are the book's, verbatim, in [`scripts/lfs/ch5-cross-toolchain.sh`](../../scripts/lfs/ch5-cross-toolchain.sh). `lfs` can't read your home folder, so copy the script into `$LFS/sources` and run it with `scripts/as-lfs.sh 'bash $LFS/sources/ch5-cross-toolchain.sh'`. It stops if the sanity check's program doesn't ask for `$LFS`'s `/lib64/ld-linux-x86-64.so.2`, and at the first failing command of any package. The chapter scripts share their unpack-build-clean helper, `scripts/lfs/build-lib.sh`, which must sit next to them.

Why cross-compile on the same CPU: the new target name forces every tool to use `$LFS` instead of Ubuntu's files. That's what makes Autark independent of the host.

## Step 4 — Temporary tools and the chroot

This step is done when you can `chroot` into `$LFS`, the temporary tools work there, and a backup tarball of the whole tree exists. Book reference: chapters 6–7.

1. As `lfs`, cross-compile the basic tools: M4, Ncurses, Bash, Coreutils, Diffutils, File, Findutils, Gawk, Grep, Gzip, Make, Patch, Sed, Tar, Xz, then Binutils and GCC (pass 2).
2. As root, change ownership of `$LFS` to root and mount the virtual filesystems (`/dev`, `/proc`, `/sys`, `/run`) inside it.
3. Enter the chroot. From here on, Ubuntu's programs are out of the picture.
4. Create the full directory tree and the essential files (`/etc/passwd`, `/etc/group`, log files).
5. Build the last temporary tools inside the chroot: Gettext, Bison, Perl, Zlib, Mpdecimal, Python, Texinfo and Util-linux. As root: `sudo LFS=/mnt/lfs bash scripts/lfs/ch7-chroot.sh` does steps 2–5 and the cleanup inside, and always unmounts the virtual filesystems afterwards.
6. Clean up, leave the chroot, and back up:

   ```
   sudo tar -cJpf ~/autark/backup-ch7.tar.xz -C $LFS .
   ```

**Checkpoint:** this backup is the restore point. If chapter 8 goes wrong, restore from it and redo chapter 8 instead of starting over.

## Step 5 — Build the final system

This step is done when all chapter 8 packages are installed, every test failure is explained, every package has a file list, and `backup-ch8.tar.xz` exists. Book reference: chapter 8. This is the longest step.

1. Run the generated script from the host, as root. It builds 81 packages in the book's order inside the chroot, starting with Man-pages and Glibc and ending with systemd, D-Bus and the cleanup:

   ```
   sudo LFS=/mnt/lfs INSIDE=ch8-inside.sh bash scripts/lfs/ch7-chroot.sh [package...]
   ```

   [`scripts/lfs/ch8-inside.sh`](../../scripts/lfs/ch8-inside.sh) is generated from the book's pages by [`scripts/lfs/ch8-gen/`](../../scripts/lfs/ch8-gen/README.md), so each package's commands are the book's, verbatim. The generator skips 25 blocks, and each skip is a rule in `gen.py`: optional docs, upgrade-only steps (nscd), alternatives (`install-locales`), and interactive commands (`tzselect`, `passwd root`, `vim -c ':options'`, `exec bash --login`). Replacements: time zone Asia/Manila, groff paper `letter`, libffi `--with-gcc-arch=x86-64-v3` instead of `native`, and glibc gets the `en_PH.UTF-8` locale.
2. **GRUB is left out.** Autark has no bootloader; the firmware starts a signed kernel image (Step 6).
3. **Autark's hardening flags** apply to every package from chapter 8 on ([decisions.md](decisions.md), "CPU target" and "Build hardening"). The script exports `CFLAGS`/`CXXFLAGS` `-O2 -march=x86-64-v3 -pipe -fstack-protector-strong -fstack-clash-protection -fcf-protection=full -D_FORTIFY_SOURCE=3` and `LDFLAGS` `-Wl,-O1 -Wl,-z,relro -Wl,-z,now`. PIE comes from GCC's `--enable-default-pie`. **Glibc is the exception:** it gets `--enable-fortify-source=3 --enable-cet` instead of those flags. Without `--enable-cet`, `-fcf-protection` in its CFLAGS makes `ld.so` fail to link (`_dl_cet_open_check` and friends missing), and glibc refuses `_FORTIFY_SOURCE` in CFLAGS and links `ld.so` itself, so it also gets no `LDFLAGS`. The rule is in `ch8-gen/gen.py`.
4. **Test failures are logged, not fatal.** A failing suite appends a line to `/sources/logs/test-failures.txt`, and the build goes on. Two suites do stop the build: GMP (needs at least 199 passes) and MPFR (needs `FAIL 0`). After the run, read `test-failures.txt` and compare each failure with the book's list of known ones. A failure the book doesn't list needs explaining before you go on. On the first build the toolchain failures were: Glibc `io/tst-lchmod`, Binutils `tmpdir/gp-gmon`, acl `test/cp.run`, and GCC's 80 (gcc) and 66 (g++) failures, which are identical to the reference LFS 13.1 build log. The full table, with the verdict on each, is in [log.md](../../log.md) ("Step 5 done").
5. **Package tracking is a before/after snapshot, not DESTDIR** (your decision, 2026-10-17). For each package the script lists every file on the filesystem before and after the install and saves the difference to `/var/lib/autark/files/<package>`. It works the same for Glibc and GCC, which the book installs straight into `/`, so no package needs a special case.
6. **Check the hardening afterwards** instead of trusting the flags:

   ```
   sudo bash scripts/lfs/hardening-scan.sh /mnt/lfs
   ```

   It scans the ELF files for PIE, RELRO, BIND_NOW and CET. The result on the first build (1260 files) was PIE 100%, RELRO 100%, CET 94%, BIND_NOW 69%. The gaps are glibc's own tools (no `LDFLAGS` by design), **Perl and everything built through it** (Perl's Configure ignores `CFLAGS`/`LDFLAGS`), and bzip2 (hard-coded flags). A Perl process therefore runs without IBT. Rebuilding Perl and bzip2 with Autark's flags is open ([log.md](../../log.md), "Open after chapter 8").
7. **Two test failures are explained by theory only.** Both are marked *not verified* in the log:
   - 82 extra libstdc++ failures (the reference has 0): probably the libstdc++ test suite reusing the build's hardened `CXXFLAGS`.
   - 9 libelf failures (the reference has 0): probably because Autark's `CFLAGS` replace autoconf's `-g -O2`, so the "-self" DWARF tests find no DWARF.

   The vim test log was deleted with its build folder, so vim's result is unverified too. Confirm the first two once by rebuilding without the hardening flags (libstdc++) and with `-g` (libelf) and re-running only those tests.
8. Back up: `sudo LFS=/mnt/lfs bash scripts/lfs/ch7-chroot.sh backup ~/autark/backup-ch8.tar.xz`, then check it with `xz -t`. Restore is the same as for chapter 7.
9. Trim the image after a big build. Deleted build files stay allocated in the sparse image (it grew to 27 GB). Allow discards on the unlocked volumes, then trim:

   ```
   sudo cryptsetup refresh --allow-discards autark
   sudo cryptsetup refresh --allow-discards autark-home
   sudo fstrim -v /mnt/lfs && sudo fstrim -v /mnt/lfs/home
   ```

   The result was 27 GB down to 3.1 GB. The trade-off: discards reveal *which* blocks are in use, not their contents. Run `fstrim` again after large builds.

Why track: to upgrade or remove a package later, you need to know exactly which files it owns. LFS records nothing on its own.

## Between Steps 5 and 6 — Disk encryption and TPM support

This step is done when the chroot's systemd shows `+LIBCRYPTSETUP +TPM2` in `systemctl --version`, and `systemd-cryptsetup`, `systemd-cryptenroll` and `ukify` run. Step 6's initramfs and boot image need all of them. Reference: BLFS 13.1-systemd.

The chapter 8 systemd is built the book's way, which leaves out three things Autark needs: `ukify` (it needs the Python `pefile` module), `libcryptsetup` (LUKS unlock) and `tpm2` (TPM+PIN enrolment). So this step builds their dependencies and rebuilds systemd. Run it like chapter 8:

```
sudo LFS=/mnt/lfs INSIDE=blfs-crypto-inside.sh bash scripts/lfs/ch7-chroot.sh
```

[`scripts/lfs/blfs-crypto-inside.sh`](../../scripts/lfs/blfs-crypto-inside.sh) builds, in this order: libaio, LVM2 (device-mapper), popt, CMake, json-c, cryptsetup, tpm2-tss, pefile, then systemd again. The script's header has the dependency diagram, and `[Autark]` comments mark each deviation from BLFS:

1. CMake is built with `--no-system-libs` (no curl, libarchive, libuv or nghttp2 yet). tpm2-tss is built with `--disable-fapi`, and its `tss` user and group are created by hand because systemd's sysusers was still off at that point.
2. The LVM2 and cryptsetup test suites are skipped: they drive the *host* kernel's device-mapper, which is holding Autark's own volumes.
3. Source verification, because three packages aren't in BLFS or have dead links: libaio's BLFS URL returns 404, so the source is Debian's `.orig` tarball (identical md5 to the one BLFS lists). tpm2-tss (GitHub release) is checked against its upstream GPG signature. pefile is the PyPI sdist, checked against PyPI's sha256. [log.md](../../log.md) ("Disk encryption and TPM support") has every hash and key.
4. The systemd rebuild enables `ukify`, `libcryptsetup` and `tpm2`. Two later fixes (found in Step 6, applied by rebuilding again): `sysusers=true`, because dracut's journald module needs `systemd-sysusers`, and `bootloader=enabled` (needs pyelftools), because `ukify` needs the `systemd-stub` file. That build also sets SBAT to name Autark.

The cryptsetup page also lists what the kernel needs for this (checked in Step 6's required options): `BLK_DEV_DM`, `DM_CRYPT`, `CRYPTO_AES`, `CRYPTO_XTS`, `CRYPTO_SHA256`, `CRYPTO_USER_API_SKCIPHER`, plus the TPM drivers.

## Step 6 — Configure, kernel and signed boot image

This step is done when Autark has a hardened kernel built for the target laptop, its firmware, zram swap, and a signed unified kernel image that the firmware starts (directly in qemu, through shim on the laptop). Book reference: chapters 9–10. Each part is one script, run like chapter 8 (`INSIDE=<script>`); the host copies `hardware/target/{kernel.config,lsmod.txt}` into `$LFS/sources` first.

1. **System identity and config** (chapter 9), [`ch9-config-inside.sh`](../../scripts/lfs/ch9-config-inside.sh), safe to re-run. It sets:
   - hostname `autark`, and `/etc/os-release` with `NAME="Autark"` and `ID=autark`;
   - systemd-networkd with DHCP on any wired link (Wi-Fi comes with Step 8);
   - systemd-resolved with DNS over TLS to Quad9 and no plain-DNS fallback;
   - the hardware clock in UTC (`LocalRTC=no`), like the Ubuntu host, US keyboard, `LANG=en_US.UTF-8`, and the book's profile, inputrc and shells;
   - `/etc/fstab` by mapper name plus the ESP's UUID, and `/etc/crypttab` for `/home` using the key file `/etc/cryptsetup-keys.d/autark-home.key` (mode 0400, enrolled from the host and tested). Root is unlocked by the initramfs from the kernel command line.
2. **Kernel**, [`ch10-kernel-inside.sh`](../../scripts/lfs/ch10-kernel-inside.sh). [`scripts/lfs/stage-profile.sh <profile>`](../../scripts/lfs/stage-profile.sh) first copies the hardware profile's inputs into `$LFS/sources` (`--generic` skips the trimming). It starts from the profile's captured config, trims it with `make localmodconfig` (when the profile has an `lsmod.txt`), applies a list of required options, then **checks every one of them in the final `.config` and stops the build on a mismatch**. The check exists because `olddefconfig` silently drops an option whose dependencies aren't met. The list is grouped by why each option is needed: what the book and systemd require (chapter 10.3), the unlock path built in (`=y`: the NVMe driver, `CONFIG_VMD` since the NVMe sits behind Intel VMD, `DM_CRYPT`, `EXT4_FS`, `EFI_STUB`, the TPM drivers), the hardening defaults from [decisions.md](decisions.md) including signed modules, and a baseline of common drivers as modules so devices plugged in later still work. Additions the check forced on the first build:
   - `KEXEC_FILE` kept coming back on because `KEXEC_HANDOVER` selects it, so `KEXEC_HANDOVER` and `CRASH_DUMP` are also off.
   - `localmodconfig` switched off the USB-net and Type-C menus, so `USB_NET_DRIVERS` and `TYPEC` are added back.
   - `DEBUG_INFO_NONE` didn't win its choice, so the other DWARF options are turned off. `GENDWARFKSYMS` is off too (it needs libdw's `dwarf.h`).
   - the firewall's `nf_tables` options, added when the firewall work (item 6) found that `NFT_CT` had been dropped.

   Each kernel build makes a new module-signing key (kept in `/root/kernel-keys/`, mode 0600), and `MODULE_SIG_FORCE` refuses any module signed by an old one. So the script deletes `/usr/lib/modules/<version>` before installing. If the target needs an out-of-tree driver, build it with its own script (`scripts/pkg/kmod-<name>.sh`), which signs it with the current key and reruns on every kernel update.
3. **zram**: `CONFIG_ZRAM` with zstd, and a service that calls `/usr/lib/autark/zram-swap`, which makes a zstd device of half the RAM and turns it on as swap. The logic is in a script (written by `ch9-config-inside.sh`) because systemd expands `$VAR` inside `ExecStart=` itself.
4. **Firmware, microcode, initramfs, boot image**, [`step6-boot-inside.sh`](../../scripts/lfs/step6-boot-inside.sh):
   - **Firmware** from linux-firmware: only this laptop's files (graphics, Wi-Fi with its `WHENCE` links, Bluetooth, the Realtek NIC), taken from `hardware/target/firmware.txt` and the baseline drivers. SOF audio firmware is not in linux-firmware; it comes from the sof-bin project (below).
   - **Microcode:** Intel's tarball carries no separate signature; the CPU itself only accepts Intel-signed microcode. The file for this CPU (`06-ba-02`) is packed as an early cpio, which loads before the rest.
   - **Initramfs** with dracut, **not host-only**: in a chroot dracut would detect the build loop device and bake that in. dracut's tpm2-tss module needs the `tpm2-tools` CLI, which Autark doesn't build, so that module is dropped, and `install_items` adds what TPM unlock needs instead (`step_initramfs` in the script):
     - the TSS libraries (libtss2 esys, mu, rc, tcti-device), which systemd loads at run time with `dlopen`. These were enough to *enrol* a TPM key, but not to unlock with it;
     - cryptsetup's token plugin, `/usr/lib/cryptsetup/libcryptsetup-token-systemd-tpm2.so`. systemd 261 unlocks TPM2 tokens through it. Without it in the initramfs, `systemd-cryptsetup` logs "cannot open shared object file", falls back to a plain passphrase prompt, and never asks for the PIN. This was found in Step 7b with a debug run of the initramfs's own `systemd-cryptsetup` ([log.md](../../log.md), "TPM2 + PIN").

     The initramfs was checked to contain `systemd-cryptsetup` (and its generator), `libcryptsetup`, the libtss2 libraries and the token plugin.
   - **Unified kernel image:** `autark.efi` (34 MB) is `systemd-stub` + kernel + initramfs + command line + os-release + SBAT, built by `ukify`. The command line is `rd.luks.name=<root LUKS UUID>=autark rd.luks.options=<root LUKS UUID>=tpm2-device=auto root=/dev/mapper/autark rw`. Two parts matter:
     - `rd.luks.options=…=tpm2-device=auto` tells the initramfs to try the TPM2+PIN token. Without it, it only asks for a passphrase. If the TPM path fails, it still falls back to the passphrase.
     - There is no `console=ttyS0`: the laptop has no serial port, and with it the passphrase prompt printed "Failed to query password: Input/output error". The qemu image of 7a had it.
5. **Signing.** Autark does not use sbctl (it is written in Go, and there is no Go on the system). systemd 261 already builds `systemd-sbsign` and `systemd-keyutil` once `bootloader=enabled`, and `ukify` signs through them. The script creates Autark's own Secure Boot **db key** with OpenSSL (RSA-2048 for the widest firmware support, SHA-256, 10 years, CN "Autark Secure Boot db 2026"):
   - The private key is `/etc/autark/secureboot/db.key` (directory 0700, key 0400) on the encrypted root. Trade-off: any root process can sign.
   - The public certificate goes on the ESP at `EFI/autark/autark-db.der`. On the laptop it is enrolled as a MOK (7b step 7), because the MSI firmware cannot add it to db.
   - `ukify` runs with `--signtool=systemd-sbsign --no-sign-kernel`. `systemd-sbsign` can't yet check whether the inner kernel is signed, and the outer signature covers the whole image anyway.

   The script **builds to `autark.efi.new` and rotates only after success**: the earlier version renamed `autark.efi` to `autark-previous.efi` *before* building, so a failed build left no `autark.efi`. The previous image stays as `autark-previous.efi`, which becomes the fallback boot entry. After each build the script also refreshes the shim copies, if shim is installed (7b step 5): `EFI/autark/grubx64.efi` = the new image, `EFI/autark-prev/grubx64.efi` = the previous one, and the removable path `EFI/BOOT/` = shim (`BOOTX64.EFI`, `mmx64.efi`) plus the current image as `grubx64.efi`. Without shim (the qemu image) `EFI/BOOT/BOOTX64.EFI` is the bare image. This is Autark's own EFI partition, so it can't overwrite Ubuntu's or Windows' fallback.
6. **Firewall and SOF audio**, [`step7-prep-inside.sh`](../../scripts/lfs/step7-prep-inside.sh). The first kernel dropped `NFT_CT` (Ubuntu's rules at capture time didn't use connection tracking), so "allow replies" was impossible. The kernel script now requires `NF_TABLES(_INET)`, `NF_CONNTRACK`, `NFT_CT`, `NFT_REJECT(_INET)`, `NFT_LIMIT` and `NFT_LOG`; rebuild the kernel before this script.
   - **nftables**: libmnl, libnftnl and nftables (built with `--with-cli=readline`, since the default libedit isn't installed). netfilter.org refuses automated downloads, so the sources are Debian's untouched upstream `.orig` tarballs, checked against the Netfilter Core Team's own `.asc` signatures. `nftables.service` is enabled, before `network-pre.target`.
   - **Ruleset** `/etc/nftables.conf`, table `inet autark`: input policy *drop*; accept established/related, loopback, the essential ICMPv6 (neighbour discovery, router advertisements, too-big, unreachable, time-exceeded, parameter-problem, MLD query), ICMPv4 errors, and DHCPv6 replies from `fe80::/10`; drop invalid; forward drop; output accept. Local additions go in one file per purpose in `/etc/nftables.d/*.nft`.
   - **SOF audio firmware** from sof-bin (an unsigned tarball from GitHub, but the DSP only runs Intel-signed firmware, and the files inside are). Raptor Lake runs Alder Lake's: `sof-adl.ri` with a `sof-rpl.ri` link (IPC3), `intel/sof-ipc4/rpl/sof-rpl.ri` (IPC4), and both `sof-hda-generic-2ch.tplg` topologies.
   - Then rebuild and sign the boot image.
7. **Laptop rebuild: audio.** The first real boot used plain HDA audio, without the digital mics. `SND_SOC_SOF_ALDERLAKE=m` was missing from the kernel: it makes no module of its own, so `localmodconfig` dropped it, and without it the kernel has no entry for this laptop's audio controller (8086:51ca, Raptor Lake, in the Alder Lake SOF family). It is now in the required list of [`ch10-kernel-inside.sh`](../../scripts/lfs/ch10-kernel-inside.sh) and checked like the rest. The next boot printed "Digital mics found on Skylake+ platform, using SOF driver" and loaded `sof-rpl.ri` and the topology.

Not decided yet: lockdown=integrity disables hibernation (confirmed in qemu), while [decisions.md](decisions.md) mentions an optional hibernate swap file. The kernel's version string says `root@Seukechi`, because the chroot borrows the host name (cosmetic).

## Step 7 — Boot it

This step is done when Autark boots from the target laptop's own disk, Secure Boot accepts your key, the disk unlocks with TPM plus PIN, and the temporary sudo rule is gone. It happens in two parts: boot the image in qemu, then move it onto the disk.

### 7a — In qemu

1. Before the first boot, set two things from the host. Add your passphrase to root A, and set the root password: `cryptsetup luksAddKey --key-file /root/autark-build.key ${LOOP}p2` (the build key file stays in slot 0 until 7b). For the password, `passwd` in a bare `chroot` fails at once ("Please use a combination…") because there is no `/dev/tty`, so it reads an empty password. Bind-mount `/dev` for that one command: `mount --bind /dev /mnt/lfs/dev`, `chroot /mnt/lfs passwd root`, then unmount it. Shadow also rejects all-lowercase passwords, so mix case and a digit.
2. Release the image completely, because qemu needs it exclusively. [`scripts/qemu-boot.sh`](../../scripts/qemu-boot.sh) refuses to start if it is still attached or unlocked:

   ```
   sudo umount -R $LFS && sudo cryptsetup close autark-home && sudo cryptsetup close autark && sudo losetup -d $LOOP
   ```
3. Boot it with `bash ~/autark/scripts/qemu-boot.sh`: UEFI firmware (OVMF), an emulated NVMe disk, the serial console in your terminal, and the whole session recorded to `qemu-boot.log`. Images built after the first real boot have no `console=ttyS0` (the laptop has no serial port), so the passphrase prompt then appears only in qemu's graphical window, not in the terminal or the log. Typed passphrases are not echoed, so they aren't in it. The firmware's variables live in a copy, `ovmf-vars.fd`, so the original stays clean.
4. Check that it asks for the disk passphrase, unlocks `/home`, you can log in, and `zramctl` shows the swap device. The result on 2026-10-17 (milestone M1, qemu half): the firmware started `autark.efi` directly, the kernel was locked down, the passphrase unlocked root, `/home` unlocked by its key file, zram gave 2 GB swap (half of 4 GB), multi-user was reached, login worked and it powered off cleanly. The only error was `virt/tdx: TDX not supported by the host platform` (qemu, harmless). qemu can't test Wi-Fi, Ethernet (the emulated NIC has no driver here), graphics, audio or the TPM; those wait for 7b.
5. **Secure Boot test, with your key.** The plain qemu boot above runs with Secure Boot off. To prove the signing, a separate test used OVMF's Secure Boot build with variables built by the host's `python3-virt-firmware`: Microsoft's standard KEK/db plus Autark's certificate *appended* to db, which mirrors the plan at the time (the MSI firmware later turned out not to allow this; see 7b step 7). Disks were opened with `snapshot=on`, so `autark.img` stayed untouched. The signed `autark.efi` was accepted ("Secure boot enabled", kernel loaded from db with "Autark Secure Boot db 2026", lockdown on, passphrase prompt reached). An unsigned image on a separate test disk was refused ("Access Denied -- rejected probably by Secure Boot"). The host's `sbverify` also gave "Signature verification OK" on `autark.efi`, `BOOTX64.EFI` and `autark-previous.efi`.

A boot failure here costs a reboot of a window, not of the laptop. Fix it from Ubuntu (attach, unlock, mount, `chroot`), rebuild the image in Step 6, and try again.

### 7b — Onto the laptop's disk

The disk has Windows, its recovery partition and Ubuntu, with no free space. Ubuntu is last, so shrinking it from its end frees space at the end of the disk, and **Autark goes after Ubuntu**. Partition order doesn't matter to the firmware.

The real disk's layout is not the image's: **ESP 1 GB, root A 40 GB, root B 15 GB, `/home` 9 GB** (65 GB in all). Root B is never copied from the image, so it can be smaller than the image's 40 GB; the first major upgrade has to fit in it ([maintenance.md](maintenance.md)).

1. Back up everything Ubuntu holds that can't be re-downloaded: uncommitted and unpushed git work, datasets, documents. A shrink that's interrupted (power, crash) can corrupt the filesystem.
2. Boot GParted Live from a USB stick, so Ubuntu isn't running, and shrink Ubuntu's partition from its end until the free space after it is at least 65 GB. ext4 can only shrink while unmounted, which is why this runs from the stick.
3. **Remove the build key, and only now.** Until the copy, the key file `/root/autark-build.key` was the way into the image. On the image's root A and `/home`, check with `cryptsetup luksDump` that a slot you can use remains, then `cryptsetup luksKillSlot` the key-file slot (slot 0 on root A) on both, and `shred -u /root/autark-build.key`. The slots are part of the partitions, so doing this before the copy removes it from the real disk too.
4. Back in Ubuntu, create four partitions in the free space (sizes above), then copy each from the image. Root B is created but not copied. Check every device name with `lsblk` first: `dd` overwrites whatever it's pointed at.

   ```
   DISK=/dev/nvme0n1                       # from lsblk; may differ
   LOOP=$(sudo losetup -rfP --show ~/autark/autark.img)   # read-only
   sudo dd if=${LOOP}p1 of=<new ESP>    bs=4M status=progress conv=fsync
   sudo dd if=${LOOP}p2 of=<new root A> bs=4M status=progress conv=fsync
   sudo dd if=${LOOP}p4 of=<new /home>  bs=4M status=progress conv=fsync
   ```

   Mark the new ESP as an EFI partition (`parted $DISK set <n> esp on`). Copying whole partitions keeps the LUKS UUIDs, so the kernel command line and `/etc/crypttab` need no edits.
5. **Shim and boot entries.** The firmware cannot trust Autark's key directly (step 7), so Autark boots through shim, the small loader Microsoft signs, copied from Ubuntu's `shim-signed` package. Each boot entry gets its own ESP folder, because shim always loads `grubx64.efi` from its own folder:

   | Folder on Autark's ESP | `grubx64.efi` is | Firmware entry |
   |---|---|---|
   | `EFI/autark/` | the current image | "Autark" → `\EFI\autark\shimx64.efi` |
   | `EFI/autark-prev/` | `autark-previous.efi` | "Autark (previous)" → `\EFI\autark-prev\shimx64.efi` |
   | `EFI/BOOT/` | the current image | none: the removable path `BOOTX64.EFI` is shim, so the firmware's own automatic entry works under Secure Boot too |

   Each folder also holds `shimx64.efi` and `mmx64.efi` (the MOK manager). `step6-boot-inside.sh` refreshes the `grubx64.efi` copies after every image build. Verify each copy with `sbverify --cert <Autark's cert>`; a missing `--cert` file is reported as "Signature verification failed", which looks like a bad signature. Create the entries (`--create` puts a new entry first in the boot order):

   ```
   sudo efibootmgr --create --disk $DISK --part <new ESP number> --label "Autark" --loader '\EFI\autark\shimx64.efi'
   sudo efibootmgr --create --disk $DISK --part <new ESP number> --label "Autark (previous)" --loader '\EFI\autark-prev\shimx64.efi'
   ```

   Then restore the boot order with `efibootmgr -o`: **Ubuntu, Windows, Autark, Autark (previous)**, so Ubuntu stays the way back and Autark is picked from the F11 menu. The firmware does list entries from a second EFI partition on this laptop. Trade-off: the shim comes from Ubuntu's package and Autark cannot update it by itself.
6. Reboot and pick Autark from the firmware boot menu. Until step 7, Secure Boot refuses the image, so check from here on that it asks for the disk passphrase, you can log in, the network comes up, `zramctl` shows the swap device, and the Wi-Fi, audio and graphics firmware all load (`journalctl -k`).
7. **Secure Boot: enrol the key as a MOK.** The plan was to append `autark-db.der` to the firmware db, keeping the MSI and Microsoft keys. The MSI setup screen cannot do that: its Key Management only offers "factory default key provisioning" and "install all factory default keys". Replacing all keys would risk Windows and Ubuntu, and leaving Secure Boot off was rejected. So the key goes into shim's own list instead (the Machine Owner Key list, MOK), which shim checks the image against ([decisions.md](decisions.md)):
   1. From Ubuntu, queue the import: `sudo mokutil --import <Autark's ESP>/EFI/autark/autark-db.der` (mount nvme0n1p6 read-only to reach it; the certificate is public), which asks for a one-time password.
   2. Reboot. At the blue MokManager screen, choose to enrol the key and give the password. It needs someone at the keyboard.
   3. Turn Secure Boot on and boot "Autark". The MOK list now holds Canonical's, Ventoy's, Ubuntu's DKMS key and "Autark Secure Boot db 2026".

   Read the first boot's journal to confirm "Secure boot enabled", Autark's cert in the kernel keyring and lockdown on.
8. **Disk unlock: TPM2 + PIN.** Run this **inside Autark**, not from Ubuntu: the TPM measurement called PCR 7 (Secure Boot state, including shim's MOK check) differs per boot path, so a key enrolled while booted into Ubuntu would never match. systemd 261 binds no PCR by default, which would let the PIN unlock regardless of Secure Boot state, so name PCR 7 explicitly:

   ```
   sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes <root device>
   sudo systemd-cryptenroll --recovery-key <root device>
   ```

   (`--wipe-slot=tpm2` replaces the first, PCR-less token; skip it if none exists.) Store the recovery key offline. The disk then has the passphrase, the recovery key and the TPM2 token as ways in. Kernel updates signed by the same key don't change PCR 7. If a boot never prompts for the PIN, check the initramfs first (Step 6.4: `tpm2-device=auto` on the command line and the token plugin in the initramfs). Done when a real boot asks for the TPM2 PIN and unlocks root with it, which it did on 2026-10-17. A harmless message, "TPM's NV index space is exhausted, skipping allocation of NvPCR", comes from `systemd-tpm2-setup`. The enrolment helper was kept on the unencrypted ESP, so remove it afterwards.
9. **You** remove the sudo rule from Ubuntu: `sudo rm /etc/sudoers.d/autark-build`, restore `/etc/bash.bashrc` from `/etc/bash.bashrc.NOUSE` (set aside in Step 2), and undo the `/bin/sh` diversion if you want dash back (Step 0). Once Autark has booted from the disk for a week, delete `autark.img`.
10. Later, at milestone M6, when Autark is the daily driver: Ubuntu's space sits *before* Autark's partitions, so `/home` can't simply grow into it. Decide then: a second encrypted volume there, or moving `/home` into it.

**Working on Autark from Ubuntu.** Two helpers unlock the real partitions after the first boot, both refusing to run unless the partition labels match, asking for your passphrase only at cryptsetup:
- [`scripts/open-autark-ro.sh`](../../scripts/open-autark-ro.sh) opens root **read-only** at `/mnt/autark-ro`, for reading Autark's journal after a boot. Close it with `sudo umount /mnt/autark-ro && sudo cryptsetup close autark-ro`.
- [`scripts/open-autark-rw.sh`](../../scripts/open-autark-rw.sh) opens root, `/home` (by its key file) and the ESP **read-write** at `/mnt/lfs`, so the Step 5–6 chroot scripts can rebuild the kernel and boot image on the real disk. Close it by unmounting `/mnt/lfs` recursively and closing `autark-home` and `autark`.

Testing images in qemu (with OVMF) is still useful for the Rust initramfs and new kernels, before they go onto the real disk.

## Step 8 — BLFS: from console to desktop

This step is done when Autark boots into Wayfire with Wi-Fi, sound and Firefox working, and your work tools installed. Reference: [BLFS, systemd edition](https://www.linuxfromscratch.org/blfs/view/stable-systemd/). Each layer depends on the one before it.

1. Basics: make-ca (TLS certificates), sudo, and OpenSSH.
2. Networking: iwd for Wi-Fi with systemd-networkd, and systemd-resolved for DNS.
3. Graphics: libdrm, Mesa with the open driver for the target's GPU (iris/anv for Intel, radeonsi/radv for AMD, nouveau/NVK for NVIDIA), Wayland, wayland-protocols and libinput.
4. Compositor: wlroots and Wayfire, built from upstream because BLFS doesn't cover them.
5. Sound, camera and Bluetooth: PipeWire and WirePlumber (with the target's audio firmware), BlueZ, and V4L2 webcam support, plus libcamera if the target has a newer Intel laptop camera.
6. Toolkit, fonts and basics: GTK4 and Rust (both needed for your shell), Geist and Geist Mono (Inter as an option), sudo-rs, foot, and rustic for backups.
7. Work tools: Firefox (hardened defaults, uBlock Origin), git, Node.js, Python packages, adb (Android platform-tools), Wine, and WebKitGTK so Galley runs.
8. Fingerprint: libfprint and fprintd, plus your out-of-tree ELAN 04f3:0c6c driver, built into the system this time so that updates stop breaking it.
9. Local AI: Ollama, built from source, plus one small model.
10. Devices and firmware updates: Android udev rules for adb, and fwupd for BIOS, SSD and dock firmware from LVFS. Printing (CUPS) is optional, for later. See [ai-layer.md](ai-layer.md).

## Step 9 — Your own desktop shell

All of this code lives in the separate `autark-tools` repo (a Rust workspace), and Autark's package recipes build it from there. This step is done when the shell pieces you wrote run on Wayfire and nothing borrowed fills their places. Pieces 1–5 come first (milestone M3); the rest follow on the roadmap. They're written in Rust with gtk4-rs, and gtk4-layer-shell pins them to screen edges.

1. Top bar, the macOS-style menu bar: clock, Wi-Fi (iwd over D-Bus), battery (UPower) and volume (PipeWire).
2. Dock: app icons with magnification on hover and indicators for running apps.
3. Spotlight-style launcher: reads `.desktop` files and opens on a hotkey.
4. Notification centre: implements the `org.freedesktop.Notifications` D-Bus service.
5. Lock screen: uses the `ext-session-lock` Wayland protocol (check that your Wayfire version supports it) and PAM for the password.
6. AI daemon `autark-ai`: a session D-Bus service that the other pieces call for Jev decisions and Ollama answers. See [ai-layer.md](ai-layer.md).
7. Rust initramfs `autark-init`: it asks for the PIN, unlocks the disk through libcryptsetup and tpm2-tss (via their Rust bindings, with no home-made crypto), mounts root and hands over to systemd. It replaces dracut once it boots reliably. The dracut image stays as a hidden fallback boot entry until then.
8. Notes app: Apple Notes on the surface, Obsidian underneath, with plain Markdown files, `[[links]]`, backlinks and a graph view. See [notes.md](notes.md).
9. `autark-stats`: a D-Bus service for system metrics (CPU, memory, disk, network, energy per app from cgroups and RAPL, battery health), polling only while something displays them.
10. Task manager: apps and processes with CPU, memory, disk, network and energy impact, and the Ctrl+Alt+Esc force-quit window. It reads from `autark-stats`.
11. Widgets: calendar and clock, battery (including Bluetooth devices), resources, Kith's tasks and suggestions, and a pinned note, shown in the notification centre and optionally on the desktop. Weather is opt-in.
12. Files app: our own, after Notes, sharing its file code.
13. `autark-pkg`: the package manager, turning `scripts/pkg/` recipes into signed packages with install, remove, upgrade, search and rollback.
14. Sandbox launcher: runs vendor binaries from `/opt` under a per-app Landlock profile.

You can start this today on Ubuntu, without waiting for the build: install Wayfire and gtk4-layer-shell from apt and develop the pieces in a Cargo workspace. The same code moves to Autark unchanged.

## How we work

Claude runs the build and you make the decisions. This guide and `~/autark/log.md` are the record, so the build can be repeated without Claude.

- **You do:** the two sudo-rule commands (Steps 1 and 7), anything that needs a password or physical access (firmware settings, USB sticks), and every new decision.
- **Claude does:** runs each step on the target laptop (Claude Code, your personal account) and records every package's build as `scripts/pkg/<name>.sh`, committed as it goes. It reports one line per finished step and stops at each checkpoint (end of Steps 4, 5 and 7).
- **Decisions that come up mid-build** (a package option, a kernel setting) come to you with a recommendation. Nothing is chosen silently.
- **Restore points:** `backup-ch7.tar.xz` and `backup-ch8.tar.xz` in `~/autark/`. A broken step means restoring and redoing, never patching over it.
- **To learn a part,** ask "why" about any step and you'll get the full explanation.

To start: run Step 0, then tell Claude "start the Autark build".
