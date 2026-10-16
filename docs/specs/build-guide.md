# Autark build guide

Step by step, from an Ubuntu host to a running Autark with your own desktop shell. Decisions behind each step are in [decisions.md](decisions.md).

## Step 0 — Prepare the Ubuntu host

This step is done when the book's version check prints no errors. Book reference: chapter 2.2, "Host System Requirements".

1. Install the missing build tools, plus qemu and its UEFI firmware for test boots:

   ```
   sudo apt install bison gawk m4 texinfo qemu-system-x86 ovmf
   ```
2. Make `/bin/sh` point to bash. Run `sudo dpkg-reconfigure dash` and answer No. Then check that `readlink -f /bin/sh` prints `/usr/bin/bash`.
3. Copy the `version-check.sh` script from chapter 2.2 into `~/autark/` and run `bash ~/autark/version-check.sh`. Every line should say OK.
4. Start the build log at `~/autark/log.md`. Write down every package you build, any changes you made, and every error. With it, the build can be repeated without Claude.

Why: LFS builds its first compiler with your Ubuntu tools, and the book's scripts use bash-only syntax. A missing tool shows up as a confusing failure an hour into the build.

## Step 1 — Create the disk image

This step is done when an empty ext4 root and an EFI partition are mounted at `/mnt/lfs`. Book reference: chapters 2.4–2.7.

1. **You** add the temporary sudo rule (it's removed in Step 7):

   ```
   echo 'tan ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/autark-build && sudo visudo -c
   ```
2. Create an 80 GB sparse image. It only uses disk space as files are written into it:

   ```
   mkdir -p ~/autark && truncate -s 80G ~/autark/autark.img
   LOOP=$(sudo losetup -fP --show ~/autark/autark.img)
   ```
3. Partition it with GPT. A 512 MB EFI partition comes first and the rest is root. There's no swap partition, because zram handles swap.

   ```
   sudo parted -s $LOOP mklabel gpt \
     mkpart ESP fat32 1MiB 513MiB set 1 esp on \
     mkpart autark ext4 513MiB 100%
   sudo mkfs.vfat -F32 -n EFI ${LOOP}p1
   sudo mkfs.ext4 -L autark ${LOOP}p2
   ```
4. Mount it and set `$LFS`, which every later step uses:

   ```
   export LFS=/mnt/lfs
   sudo mkdir -p $LFS && sudo mount ${LOOP}p2 $LFS
   sudo mkdir -p $LFS/boot/efi && sudo mount ${LOOP}p1 $LFS/boot/efi
   ```

After a reboot, re-attach the image with `losetup -fP` and run the two mount commands again before continuing.

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
4. Give `lfs` a clean shell: the book's `.bash_profile` and `.bashrc`, plus `export MAKEFLAGS=-j8` to use all 8 threads.

Why a separate user: the cross-toolchain must not pick up Ubuntu's libraries or environment variables. A fresh login with an almost-empty environment is the simplest guarantee.

## Step 3 — Build the cross-toolchain

This step is done when a test program compiled with the new toolchain links against `/lib64/ld-linux-x86-64.so.2` inside `$LFS`, not Ubuntu's copy. Book reference: chapter 5. Runs as the `lfs` user.

1. Binutils, pass 1: the assembler and linker, built to target `x86_64-lfs-linux-gnu`. Its build time sets the book's time unit (SBU), and Claude times it to estimate the rest of the build.
2. GCC, pass 1: a C/C++ compiler with no C library yet.
3. Linux API headers: the kernel interface that glibc compiles against.
4. Glibc: the C library, built with the pass-1 compiler. Then run the book's sanity check, and stop if it fails.
5. Libstdc++: the C++ standard library, so that later C++ packages can build.

Why cross-compile on the same CPU: the new target name forces every tool to use `$LFS` instead of Ubuntu's files. That's what makes Autark independent of the host.

## Step 4 — Temporary tools and the chroot

This step is done when you can `chroot` into `$LFS`, the temporary tools work there, and a backup tarball of the whole tree exists. Book reference: chapters 6–7.

1. As `lfs`, cross-compile the basic tools: M4, Ncurses, Bash, Coreutils, Diffutils, File, Findutils, Gawk, Grep, Gzip, Make, Patch, Sed, Tar, Xz, then Binutils and GCC (pass 2).
2. As root, change ownership of `$LFS` to root and mount the virtual filesystems (`/dev`, `/proc`, `/sys`, `/run`) inside it.
3. Enter the chroot. From here on, Ubuntu's programs are out of the picture.
4. Create the full directory tree and the essential files (`/etc/passwd`, `/etc/group`, log files).
5. Build the last temporary tools inside the chroot: Gettext, Bison, Perl, Python, Texinfo and Util-linux.
6. Clean up, leave the chroot, and back up:

   ```
   sudo tar -cJpf ~/autark/backup-ch7.tar.xz -C $LFS .
   ```

**Checkpoint:** this backup is the restore point. If chapter 8 goes wrong, restore from it and redo chapter 8 instead of starting over.

## Step 5 — Build the final system

This step is done when all chapter 8 packages are installed, the toolchain test suites pass, and every package has a file list. Book reference: chapter 8. This is the longest step.

1. Build roughly 80 packages in the book's order, starting with Man-pages and Glibc and ending with systemd, D-Bus and the cleanup.
2. Run the test suites for Glibc, Binutils and GCC, and compare the failures against the book's list of known ones. A toolchain that fails its tests is not usable.
3. Track packages (your decision): install each package into a staging directory, save its file list, then copy it into `/`:

   ```
   make DESTDIR=/tmp/pkg/$NAME install
   (cd /tmp/pkg/$NAME && find . -type f -o -type l) > /var/lib/autark/files/$NAME-$VER
   cp -a /tmp/pkg/$NAME/. /
   ```

   Glibc and GCC install straight into `/`, as the book says. For those, the file list comes from a before/after snapshot.
4. Back up again: `backup-ch8.tar.xz`.

Why track: to upgrade or remove a package later, you need to know exactly which files it owns. LFS records nothing on its own.

## Step 6 — Configure, kernel and bootloader

This step is done when the image has a kernel built for this laptop, its firmware, zram swap and a GRUB that boots from the EFI partition. Book reference: chapters 9–10, plus BLFS for UEFI GRUB.

1. System identity and config (chapter 9): hostname `autark`, `/etc/os-release` with `NAME="Autark"` and `ID=autark`, systemd-networkd for Ethernet, and locale, timezone and keyboard copied from your Ubuntu settings.
2. Kernel, trimmed to this laptop. Start from Ubuntu's config and keep only the modules your hardware loads:

   ```
   cp ~/autark/hardware/kernel.config .config
   make localmodconfig LSMOD=~/autark/hardware/lsmod.txt
   ```

   Then build the boot path into the kernel (`=y`, not a module), so no initramfs is needed: `CONFIG_VMD` (your NVMe sits behind Intel VMD), `CONFIG_BLK_DEV_NVME`, `CONFIG_EXT4_FS` and `CONFIG_EFI_STUB`. Also check that the systemd options from chapter 10.3 are set.
3. Firmware from linux-firmware, copied into `/lib/firmware`. These are the exact files this laptop loads:

   | Device | Firmware file |
   | --- | --- |
   | Iris Xe graphics | `i915/tgl_dmc_ver2_12.bin` (plus the tgl GuC/HuC files) |
   | AX201 Wi-Fi | `iwlwifi-QuZ-a0-hr-b0-77.ucode` |
   | Bluetooth | `intel/ibt-19-0-4.sfi` |
   | Audio (SOF) | `intel/sof/sof-tgl.ri` plus its topology files |

4. zram (your memory-management choice): build `CONFIG_ZRAM` with zstd compression, then add a systemd unit that creates a zstd zram device sized at half of RAM with `zramctl` and turns it on as swap.
5. GRUB for UEFI (BLFS): build popt, efivar and efibootmgr, then GRUB with `--with-platform=efi`. Install it on the removable-media path so it boots in qemu and on any machine without firmware boot entries:

   ```
   grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable
   ```

   In `grub.cfg`, boot with `root=PARTUUID=<root partition>`. With no initramfs, the kernel can't look up a filesystem label.

## Step 7 — Boot it

This step is done when Autark boots on this laptop's real hardware from a USB stick, and the temporary sudo rule is gone.

1. Unmount the image and detach the loop device, then boot it in a VM:

   ```
   sudo umount -R $LFS && sudo losetup -d $LOOP
   qemu-system-x86_64 -enable-kvm -m 4G -smp 4 -bios /usr/share/ovmf/OVMF.fd \
     -drive file=~/autark/autark.img,format=raw
   ```

   Check that GRUB shows Autark, you can log in, the network comes up, and `zramctl` shows the swap device.
2. Real hardware without touching Ubuntu: write the image to a USB stick of 64 GB or more, turn off Secure Boot, and boot the stick from the firmware boot menu. Check that Wi-Fi firmware, audio and graphics all load (`journalctl -k`), because qemu can't test those.
3. **You** remove the sudo rule: `sudo rm /etc/sudoers.d/autark-build`.
4. Later, to move to the other laptop: write the image to its disk from a live USB, then grow the root partition to fill the disk (`sgdisk -e`, `growpart`, `resize2fs`). Any hardware that differs from this laptop needs its own modules and firmware added first.

## Step 8 — BLFS: from console to desktop

This step is done when Autark boots into Wayfire with Wi-Fi, sound and Firefox working, and your work tools installed. Reference: [BLFS, systemd edition](https://www.linuxfromscratch.org/blfs/view/stable-systemd/). Each layer depends on the one before it.

1. Basics: make-ca (TLS certificates), sudo, and OpenSSH.
2. Networking: iwd for Wi-Fi with systemd-networkd, and systemd-resolved for DNS.
3. Graphics: libdrm, Mesa (the Iris driver for your Iris Xe), Wayland, wayland-protocols and libinput.
4. Compositor: wlroots and Wayfire, built from upstream because BLFS doesn't cover them.
5. Sound: PipeWire and WirePlumber, with your SOF audio firmware.
6. Toolkit and fonts: GTK4 and Rust (both needed for your shell), Inter and a monospace font.
7. Work tools: Firefox, git, Node.js, Python packages, adb (Android platform-tools), and Wine.
8. Fingerprint: libfprint and fprintd, plus your out-of-tree ELAN 04f3:0c6c driver, built into the system this time so that updates stop breaking it.
9. Local AI: Ollama, built from source, plus one small model. See [ai-layer.md](ai-layer.md).

## Step 9 — Your own desktop shell

This step is done when the five shell pieces you wrote run on Wayfire and nothing borrowed fills their places. They're written in Rust with gtk4-rs, and gtk4-layer-shell pins them to screen edges.

1. Top bar, the macOS-style menu bar: clock, Wi-Fi (iwd over D-Bus), battery (UPower) and volume (PipeWire).
2. Dock: app icons with magnification on hover and indicators for running apps.
3. Spotlight-style launcher: reads `.desktop` files and opens on a hotkey.
4. Notification centre: implements the `org.freedesktop.Notifications` D-Bus service.
5. Lock screen: uses the `ext-session-lock` Wayland protocol (check that your Wayfire version supports it) and PAM for the password.
6. AI daemon `autark-ai`: a session D-Bus service that the other pieces call for Jev decisions and Ollama answers. See [ai-layer.md](ai-layer.md).

You can start this today on Ubuntu, without waiting for the build: install Wayfire and gtk4-layer-shell from apt and develop the pieces in a Cargo workspace. The same code moves to Autark unchanged.

## How we work

Claude runs the build and you make the decisions. This guide and `~/autark/log.md` are the record, so the build can be repeated without Claude.

- **You do:** the two sudo-rule commands (Steps 1 and 7), anything that needs a password or physical access (firmware settings, USB sticks), and every new decision.
- **Claude does:** runs each step and adds every command to a script in `~/autark/scripts/`. It reports one line per finished step and stops at each checkpoint (end of Steps 4, 5 and 7).
- **Decisions that come up mid-build** (a package option, a kernel setting) come to you with a recommendation. Nothing is chosen silently.
- **Restore points:** `backup-ch7.tar.xz` and `backup-ch8.tar.xz` in `~/autark/`. A broken step means restoring and redoing, never patching over it.
- **To learn a part,** ask "why" about any step and you'll get the full explanation.

To start: run Step 0, then tell Claude "start the Autark build".
