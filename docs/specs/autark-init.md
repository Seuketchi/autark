# autark-init (M4: the Rust initramfs)

`autark-init` is the first program the kernel runs from the initramfs. It replaces dracut's shell scripts with one Rust binary that
asks for the TPM PIN, unlocks the disk, mounts root and becomes systemd. The cryptography stays in libcryptsetup and its systemd TPM2
token plugin (which talks to the TPM through tpm2-tss): this program passes a PIN in and gets "opened" or an error back, and has no
key handling or TPM protocol of its own. The code is `crates/autark-init` in autark-tools.

## What it does, in order

1. Mount `/proc`, `/sys`, `/dev` (devtmpfs) and `/run`; put the console on standard input, output and error.
2. Read `/proc/cmdline`: `rd.luks.name=<UUID>=<name>`, `rd.luks.options=<UUID>=…` (`tpm2-device=auto` asks for the TPM, `discard`,
   `no-read-workqueue`, `no-write-workqueue`), `root=`, `rootfstype=`, `rootflags=`, `ro`/`rw`, `init=`, `rd.timeout=`. These are the names
   dracut and systemd-cryptsetup read, so **one command line boots either initramfs**.
3. For each volume: look for the device by scanning `/sys/class/block` and asking libcryptsetup which LUKS2 header carries the UUID
   (there is no udev, so no `/dev/disk/by-uuid`), retrying every 250 ms until `rd.timeout` (default 30 s).
4. Open it: the TPM token first when asked, then the PIN if the token wants one (up to **3** tries, the same as systemd-cryptsetup, so a
   wrong PIN can't be tried without limit against the TPM's lockout counter), then a passphrase or recovery key (3 tries).
5. Mount `root=` on `/sysroot` (generic `rootflags=` such as `noatime` become mount flags; the rest goes to the file system).
6. Hand over as `switch_root` does: empty the initramfs (only if `/` is a ram file system), move `/proc /sys /dev /run` into the new root,
   move the new root onto `/`, `chroot`, and `exec /usr/lib/systemd/systemd` (or `init=`) as PID 1.
7. On any failure: say what went wrong, wait for Enter, restart. PID 1 never exits or panics (that would be a kernel panic).

Run anywhere but as PID 1 it only does read-only checks: `autark-init parse [file]`, `scan`, and `check <device-or-image> [--tpm2]`
(the real unlock questions, activating nothing).

## What has been tested, and what hasn't

| | Tested | How |
| --- | --- | --- |
| Command-line parsing (UUID forms, option lists, quotes, `ro`/`rw`) | ✅ | 9 unit tests |
| The unlock order and limits (TPM → PIN ×3 → passphrase ×3, fallbacks, lockout, nobody answering) | ✅ | 10 unit tests with a scripted fake volume and keyboard |
| Device scanning rules, `rootflags` splitting, `init=` choice | ✅ | 7 unit tests |
| The real libcryptsetup: open a LUKS2 volume, wrong passphrase, retries, give up, not-LUKS, TPM requested but absent → passphrase | ✅ | 6 integration tests on a LUKS2 image file, no root |
| The TPM token and PIN with a real TPM | ⬜ | needs swtpm in qemu, then the laptop |
| Device-mapper node creation with no udev running | ⬜ | qemu; the main open question (below) |
| Mounting root and `switch_root` into systemd | ⬜ | qemu |
| Console and keyboard in the initramfs | ⬜ | qemu, then the laptop |

## What is still to write

1. **The image.** `scripts/lfs/step6-initramfs-rust.sh`: collect `autark-init`, the glibc loader and every shared library it needs (`ldd`),
   libcryptsetup and its dependencies, the token plugin `/usr/lib/cryptsetup/libcryptsetup-token-systemd-tpm2.so`, and the libtss2 libraries
   it loads with `dlopen` (esys, mu, rc, tcti-device); pack them as a zstd cpio after the microcode cpio. dracut's image already shows which
   libraries are needed (`lsinitrd`).
2. **A second boot image.** `ukify` builds `autark-rust.efi` from the same kernel and command line with the new initramfs, signed with the same
   key; add it as its own firmware entry (`efibootmgr`). **`autark.efi` (dracut) is never replaced**; it stays the default until the Rust one has
   booted reliably, and then stays as the hidden fallback ([roadmap](roadmap.md), M4).
3. **qemu tests** (on Ubuntu, with OVMF and `swtpm`): a disk with a LUKS2 root enrolled for TPM2 + PIN (`systemd-cryptenroll`), boot the
   kernel 7.1.8 and the new initramfs, and check each case: right PIN; wrong PIN three times then the passphrase; no TPM; recovery key; a
   missing disk (timeout and restart message); a bad `root=`.
4. **The laptop.** Boot the Rust entry once from the firmware menu with dracut one entry away. The TPM token binds PCR 7 (Secure Boot state),
   not the image, so a differently built image signed by the same key still unlocks.

## Open questions and risks

- **No udev.** `libdevmapper` creates `/dev/mapper/<name>` itself when udev isn't running, as far as I know; this must be confirmed in qemu.
  If it isn't so, the fix is to run `systemd-udevd` in the initramfs as dracut does, which makes the image bigger but changes little else.
- **Which error means "wrong PIN".** The token plugin's error codes for a refused PIN versus a missing or locked TPM were not checked
  against a real TPM. The code counts anything it doesn't recognise as a refused PIN, so the limit of three holds either way.
- **USB keyboards.** The laptop's own keyboard (PS/2 `i8042`/`atkbd`), NVMe, ext4, dm-crypt and the TPM drivers are built into the kernel, so
  `autark-init` loads no modules. USB and I2C HID are modules, and `MODULE_SIG_FORCE` only accepts ones signed by the current key, so an
  external USB keyboard won't type the PIN until module loading is added (or those drivers are built in).
- **Secrets.** The PIN and passphrase are read without echo into a buffer that is wiped on drop; nothing secret is logged. libcryptsetup keeps
  its own copy while it works.
