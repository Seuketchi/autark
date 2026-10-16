# Autark build guide

Step by step, from an Ubuntu host to a running Autark with your own desktop shell. Decisions behind each step are in [decisions.md](decisions.md).

## Step 0 — Prepare the target laptop

Autark is built on the laptop it will run on, never on the work laptop. This step is done when the target laptop runs a temporary Ubuntu host, its hardware profile is in the repo, and the book's version check prints no errors. Book reference: chapter 2.2, "Host System Requirements".

1. Install Ubuntu on the target laptop with manual partitioning. Put a 1 GB EFI partition first, leave the middle of the disk unallocated for Autark, and give Ubuntu 60 GB **at the end** of the disk. Autark's `/home` can then grow into Ubuntu's space once Ubuntu is gone.
2. Clone this repo to `~/autark`. Plug in and use every device you own first (dock, external monitor, headset, phone, USB drives, webcam, Bluetooth devices), so their drivers are loaded. Then capture the hardware profile, which becomes the standard the kernel and firmware steps use:

   ```
   bash ~/autark/scripts/capture-hardware.sh target
   ```

   Commit `hardware/target/`. The work laptop's profile stays in `hardware/work-laptop/` as a reference.
3. Install the missing build tools, plus qemu and its UEFI firmware for testing images:

   ```
   sudo apt install bison gawk m4 texinfo cryptsetup efibootmgr qemu-system-x86 ovmf
   ```
4. Make `/bin/sh` point to bash. Run `sudo dpkg-reconfigure dash` and answer No. Then check that `readlink -f /bin/sh` prints `/usr/bin/bash`.
5. Copy the `version-check.sh` script from chapter 2.2 into `~/autark/` and run `bash ~/autark/version-check.sh`. Every line should say OK.
6. Install Claude Code and sign in with your **personal** Claude account; the company seat stays on the work laptop.
7. Start the build log at `~/autark/log.md`. Write down every package you build, any changes you made, and every error. With it, the build can be repeated without Claude.

Why: LFS builds its first compiler with the host's tools, and the book's scripts use bash-only syntax. A missing tool shows up as a confusing failure an hour into the build.

## Step 1 — Create the encrypted Autark partition

This step is done when encrypted root A is mounted at `/mnt/lfs`, encrypted `/home` at `/mnt/lfs/home`, and the EFI partition at `/mnt/lfs/boot/efi`. Root B is created but left empty for the first major upgrade ([maintenance.md](maintenance.md)). Book reference: chapters 2.4–2.7.

1. **You** add the temporary sudo rule, on the target laptop only. It's removed in Step 7:

   ```
   echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/autark-build && sudo visudo -c
   ```
2. Check the disk's device name with `lsblk`, then create three partitions in the unallocated middle of the disk: root A (80 GB), root B (80 GB) and `/home` (everything up to Ubuntu's partition). There's no swap partition, because zram handles swap.

   ```
   DISK=/dev/nvme0n1                      # from lsblk; may differ
   sudo parted $DISK mkpart autark-a ext4 <start of free space> +80GiB
   sudo parted $DISK mkpart autark-b ext4 <end of autark-a> +80GiB
   sudo parted $DISK mkpart autark-home ext4 <end of autark-b> <start of Ubuntu's partition>
   ```
3. Encrypt root A and `/home` with LUKS2 and format them. Root B stays unformatted until the first upgrade.

   ```
   AUTARK=${DISK}p2; HOME_PART=${DISK}p4  # check the numbers with lsblk
   sudo cryptsetup luksFormat --type luks2 $AUTARK
   sudo cryptsetup luksFormat --type luks2 $HOME_PART
   sudo cryptsetup open $AUTARK autark
   sudo cryptsetup open $HOME_PART autark-home
   sudo mkfs.ext4 -L autark-a /dev/mapper/autark
   sudo mkfs.ext4 -L autark-home /dev/mapper/autark-home
   ```

   At boot, `/home` unlocks with a key file stored inside the unlocked root (listed in `/etc/crypttab`), so you only enter the PIN once.
4. Mount it and set `$LFS`, which every later step uses. Autark shares the EFI partition with the temporary Ubuntu:

   ```
   export LFS=/mnt/lfs
   sudo mkdir -p $LFS && sudo mount /dev/mapper/autark $LFS
   sudo mkdir -p $LFS/home && sudo mount /dev/mapper/autark-home $LFS/home
   sudo mkdir -p $LFS/boot/efi && sudo mount ${DISK}p1 $LFS/boot/efi
   ```

The partition unlocks with a passphrase for now. TPM-plus-PIN unlocking is added in Step 7.

After a reboot, unlock it with `cryptsetup open` and run the two mount commands again before continuing.

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
4. Give `lfs` a clean shell: the book's `.bash_profile` and `.bashrc`, plus `export MAKEFLAGS=-j$(nproc)` to use every CPU thread.

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

## Step 6 — Configure, kernel and signed boot image

This step is done when Autark has a hardened kernel built for the target laptop, its firmware, zram swap, and a signed unified kernel image that the firmware starts directly. Book reference: chapters 9–10.

1. System identity and config (chapter 9): hostname `autark`, `/etc/os-release` with `NAME="Autark"` and `ID=autark`, systemd-networkd for Ethernet, and locale, timezone and keyboard copied from your Ubuntu settings.
2. Kernel, trimmed to the target laptop. Start from its Ubuntu config and keep only the modules its hardware loads:

   ```
   cp ~/autark/hardware/target/kernel.config .config
   make localmodconfig LSMOD=~/autark/hardware/target/lsmod.txt
   ```

   Then build everything the unlock path needs into the kernel (`=y`, not a module): the storage controller from `hardware/target/lspci.txt` (for NVMe, `CONFIG_BLK_DEV_NVME`, plus `CONFIG_VMD` if it sits behind Intel VMD, as on the work laptop), `CONFIG_DM_CRYPT`, `CONFIG_EXT4_FS`, `CONFIG_EFI_STUB`, and the TPM drivers (`CONFIG_TCG_TPM`, `CONFIG_TCG_CRB`). Add the kernel hardening defaults from [decisions.md](decisions.md), including signed modules. Also check that the systemd options from chapter 10.3 are set.

   Then add a baseline of common drivers as loadable modules, so devices plugged in later still work: USB storage (`usb-storage`, `uas`), input (`usbhid`, `hid-generic`, `hid-multitouch`), USB networking and serial (`cdc_ether`, `r8152`, `cdc_acm`), webcams (`uvcvideo`), USB audio (`snd-usb-audio`), Bluetooth (`btusb`), USB-C and Thunderbolt (`typec_ucsi`, `thunderbolt`), and filesystems (`vfat`, `exfat`, `ntfs3`, `iso9660`, `udf`, `fuse`).

   If the target needs an out-of-tree driver, build it with its own script (`scripts/pkg/kmod-<name>.sh`), which signs it with your module key. The script reruns on every kernel update.
3. Firmware from linux-firmware, copied into `/lib/firmware`: exactly the files listed in `hardware/target/firmware.txt`, which Step 0 captured, plus the firmware for the baseline drivers above and the CPU microcode (Intel's microcode repository, or `amd-ucode` from linux-firmware). For comparison, the work laptop needs four (`hardware/work-laptop/firmware.txt`).
4. zram (your memory-management choice): build `CONFIG_ZRAM` with zstd compression, then add a systemd unit that creates a zstd zram device sized at half of RAM with `zramctl` and turns it on as swap.
5. Initramfs and signed boot image. The first boot uses dracut, with its systemd and TPM2 modules. Our Rust initramfs replaces it in Step 9. Combine the kernel, the CPU microcode (first, so it loads before anything else), the initramfs and the kernel command line (`rd.luks.name=<LUKS UUID>=autark root=/dev/mapper/autark`) into one unified kernel image with `ukify`. Then create your Secure Boot keys and sign the image:

   ```
   ukify build --linux=vmlinuz --initrd=microcode.img --initrd=initramfs.img --cmdline=@cmdline --output=/boot/efi/EFI/Linux/autark.efi
   sbctl create-keys
   sbctl sign /boot/efi/EFI/Linux/autark.efi
   ```

   There's no bootloader: the firmware starts the signed image directly, through boot entries added in Step 7. Leave `EFI/BOOT/BOOTX64.EFI` alone, since it's the temporary Ubuntu's fallback. Keep the previous image as `autark-previous.efi`; it becomes the fallback boot entry.

## Step 7 — Boot it

This step is done when Autark boots from the target laptop's own disk, Secure Boot uses your keys, the disk unlocks with TPM plus PIN, and the temporary sudo rule is gone.

1. Unmount and lock the partitions: `sudo umount -R $LFS && sudo cryptsetup close autark-home && sudo cryptsetup close autark`.
2. Add firmware boot entries for Autark and its fallback. Ubuntu's entry stays as the way back:

   ```
   sudo efibootmgr --create --disk $DISK --part 1 --label "Autark" --loader '\EFI\Linux\autark.efi'
   sudo efibootmgr --create --disk $DISK --part 1 --label "Autark (previous)" --loader '\EFI\Linux\autark-previous.efi'
   ```
3. Reboot and pick Autark from the firmware boot menu. Check that it asks for the disk passphrase, you can log in, the network comes up, `zramctl` shows the swap device, and the Wi-Fi, audio and graphics firmware all load (`journalctl -k`).
4. **Secure Boot:** put the firmware in setup mode and run `sbctl enroll-keys --microsoft`. Keeping Microsoft's keys alongside yours lets the temporary Ubuntu and firmware add-ons still boot.
5. **Disk unlock:** run `systemd-cryptenroll --tpm2-device=auto --tpm2-with-pin=yes`, plus `--recovery-key`. Store the recovery key offline.
6. **You** remove the sudo rule from Ubuntu: `sudo rm /etc/sudoers.d/autark-build`.
7. Later, at milestone M6, when Autark is the daily driver: delete the Ubuntu partition and its boot entry, then grow `/home` into the freed space (`parted resizepart`, `cryptsetup resize autark-home`, `resize2fs /dev/mapper/autark-home`).

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
