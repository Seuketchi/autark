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
| The initramfs image: every library it and the TPM plugin need, and a real LUKS2 unlock (wrong passphrase refused, right one accepted) from inside a chroot of only the image's 19 files | ✅ | `scripts/autark-rust-initramfs.sh build selftest`, no root (6.6 MB; dracut's is 19 MB) |
| The signed boot image, the firmware entry, the one-time boot | ⬜ | the script's `uki`, `entry` and `try` steps, which need root and haven't been run |
| The TPM token and PIN with a real TPM | ⬜ | needs swtpm in qemu, then the laptop |
| Device-mapper node creation with no udev running | ⬜ | qemu; the main open question (below) |
| Mounting root and `switch_root` into systemd | ⬜ | qemu |
| Console and keyboard in the initramfs | ⬜ | qemu, then the laptop |

## The script, and how it stays safe

`scripts/autark-rust-initramfs.sh` has one step per command: `build`, `selftest`, `uki`, `entry`, `try`, `status`, `remove`.

- `build` and `selftest` work as any user and touch nothing outside their work folder (set `WORK` and `OUT`).
- `uki` builds a second signed boot image into `EFI/autark-rust/` with shim beside it, the same way `EFI/autark/` is laid out. `autark.efi`, dracut's
  image and `/etc/kernel/cmdline` are never changed.
- `entry` adds a firmware entry "Autark (Rust initramfs, test)" and then **puts BootOrder back exactly as it was**, so the machine keeps booting dracut.
- `try` sets BootNext: the next boot, and only that one, starts the Rust image. If it fails, the boot after is the normal one. The TPM token binds
  PCR 7 (Secure Boot state), and the same shim and key are used, so the TPM should release the key.
- `remove` deletes the entry, the boot image and the initramfs.

## Still to do

1. Run `uki`, `entry` and `try` as root on the laptop, or (better first) the qemu tests below.
2. **qemu tests** (on Ubuntu, with OVMF and `swtpm`): a disk with a LUKS2 root enrolled for TPM2 + PIN (`systemd-cryptenroll`), boot the
   kernel 7.1.8 and the new initramfs, and check each case: right PIN; wrong PIN three times then the passphrase; no TPM; recovery key; a
   missing disk (timeout and restart message); a bad `root=`.
3. Make it the default only after it has booted reliably, and keep dracut as the hidden fallback ([roadmap](roadmap.md), M4).

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
