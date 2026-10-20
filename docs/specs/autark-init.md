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
| The signed boot image, the firmware entry, the test boot | ✅ | the script's `build selftest uki entry` then `try`, on the laptop (2026-10-20): shim and Secure Boot accepted the image, the kernel booted it, `BootCurrent` was the test entry, and systemd's boot time shows no initrd stage |
| The TPM token and PIN | ✅ | qemu with a software TPM: `enroll`, `tpm-pin`, `tpm-wrong-pin`, `recovery-key`. On the laptop's real TPM (2026-10-20) the PIN alone unlocks the disk, once the init does the OS-separator extend (below) |
| Device-mapper node creation with no udev running | ✅ | qemu: `/dev/mapper/autark` appears and root mounts, with no udev in the image |
| Mounting root and `switch_root` | ✅ | qemu: the test init runs as PID 1 on the unlocked root, with `/proc`, `/sys`, `/dev` and `/run` moved over and the initramfs gone. Into systemd itself: ⬜ (the laptop) |
| Console and keyboard in the initramfs | ✅ | qemu types at `ttyS0`; on the laptop the disk was unlocked from its own keyboard and screen |
| The boot splash | ✅ | on the laptop's real screen (2026-10-20), with `autark.splash=1`; see [boot-splash.md](boot-splash.md) |

## The TPM and the OS separator

The first real-TPM test boot asked for the PIN and then for the recovery passphrase: the TPM answered "policy does not match" and the init fell back. The cause:

- systemd 261's initramfs starts with "TPM PCR OS Separator", which extends PCRs 0-7 with `sha256("os-separator")`.
- A key enrolled from the running system (`systemd-cryptenroll --tpm2-pcrs=7 --tpm2-with-pin=yes`) is therefore sealed to PCR 7 *after* that extend.
- The init is not systemd, so it unsealed at the firmware's own value and the TPM refused.

Checked with the real numbers: the firmware's event log replays to PCR 7 = `FE18323E…`; the dracut boot reads `D635820E…` = `sha256(FE18323E… ‖ sha256("os-separator"))`; and the LUKS token's policy hash is exactly PolicyPCR(`D635820E…`) followed by PolicyAuthValue (the PIN).

`src/tpm.rs` does the same extend before the first unlock attempt: one raw `TPM2_PCR_Extend` per PCR 0-7 on `/dev/tpmrm0` (no TPM library). It runs only when a volume has `tpm2`; if it fails the init logs why and carries on, since the recovery passphrase still works. `check` doesn't extend (it runs on a live system that already has). After an init boot the live PCR 7 reads the same as after a dracut boot, so a key enrolled from either boot works for both.

If the TPM ever refuses again, the same two numbers are the quick check: replay the firmware log (`/sys/kernel/security/tpm0/binary_bios_measurements`, root) and compare with the live `/sys/class/tpm/tpm0/pcr-sha256/7`.

## Debugging a test boot

A boot that freezes leaves nothing in pstore here (`CONFIG_EFI_VARS_PSTORE` is a module), so the init keeps its own log:

- Always: breadcrumbs on the kernel log, `journalctl -b -k | grep autark-init`. They never include the PIN or its length.
- With `autark.log=<device>` on the command line (the ESP, e.g. `autark.log=/dev/nvme0n1p6`): the same lines are appended to `EFI/autark-rust/init.log` on that FAT partition, synced after every line, so they survive a hang.
- `autark.splash=1` turns the splash on; if the framebuffer or fonts are unavailable the init says why in this log and uses the text prompt.

## The script, and how it stays safe

`scripts/autark-rust-initramfs.sh` has one step per command: `build`, `selftest`, `uki`, `entry`, `try`, `untry`, `default`, `undefault`, `status`, `remove`.

- `build` and `selftest` work as any user and touch nothing outside their work folder (set `WORK` and `OUT`).
- `uki` builds a second signed boot image into `EFI/autark-rust/` with shim beside it, the same way `EFI/autark/` is laid out. `autark.efi`, dracut's
  image and `/etc/kernel/cmdline` are never changed.
- `entry` adds a firmware entry "Autark (Rust initramfs, test)" and then **puts BootOrder back exactly as it was**, so the machine keeps booting dracut.
- `try` makes the next boot start the Rust image. This laptop's firmware **ignores BootNext** and its F11 menu doesn't list the test entry, so `try` also puts
  the entry first in BootOrder (saving the old order), and `untry` puts the order back. Don't press F11 for the test boot. If it freezes, hold the power button,
  press F11, pick plain Autark and run `untry`. The TPM token binds PCR 7 (Secure Boot state); see the next section for what else the init must do for the TPM to release the key.
- `untry` restores the BootOrder that `try` saved. Run it after the test boot, whatever happened.
- `default` makes the Rust image the **normal "Autark" entry**: it copies the Rust boot image over `EFI/autark/grubx64.efi` (through a temporary file) and puts dracut's image (`EFI/Linux/autark.efi`) in `EFI/autark-prev/`, so "Autark (previous)" is now dracut's image for the current kernel (what was there is kept as `grubx64.efi.before-rust`). The firmware entries, BootOrder, `EFI/BOOT` (the "UEFI OS" fallback) and `autark.efi` are not touched. It refuses if the Rust image isn't for the running kernel. `status` says which init is the default.
- `undefault` puts dracut's image back as the normal entry.
- **After a kernel update** step 6's `uki` puts dracut's image back in `EFI/autark` (a safe direction), so run `build uki default` again for the new kernel. If the Rust image fails to boot: hold the power button, press F11, pick "Autark (previous)", then `undefault`.
- `remove` deletes the entry, the boot image and the initramfs.

## The qemu test

`scripts/qemu-test/` has three parts. **All 10 cases pass** (run on the Ubuntu partition on 2026-10-20: the first run found two bugs in the test itself, not in `autark-init`: the software TPM was started once but exits when qemu disconnects, and the recovery key was read before the whole line had arrived; the last two cases were rerun on their own after the fixes).

1. On Autark, as you: `cd ~/autark-tools && cargo build --release -p autark-init`, then `sh ~/autark/scripts/qemu-test/autark-init-bundle.sh`.
   It writes `~/autark-init-test-bundle.tar` (about 42 MB): the kernel, the Rust initramfs, and a small root for the test disk with a test init
   (`autark-init-test-payload`) and `systemd-cryptenroll`. It changes nothing on Autark.
2. Carry the tarball to the machine with qemu: a USB stick, or from Ubuntu with `scripts/open-autark-ro.sh`.
3. There: `sudo apt install qemu-system-x86 swtpm cryptsetup e2fsprogs`, then
   `sudo python3 autark-init-qemu-test.py autark-init-test-bundle.tar` (`--slow` without KVM, `--keep` to keep the disk and the console logs,
   `--only NAME…` for some cases). It builds a LUKS2 disk, starts a software TPM, and boots the kernel and initramfs in qemu, typing at the
   console. A few minutes with KVM.

| Case | What it checks |
| --- | --- |
| `passphrase` | the right passphrase unlocks, root mounts, and the test init runs as PID 1 on it with `/proc`, `/sys`, `/dev`, `/run` moved over and the initramfs gone |
| `passphrase-retry` | a wrong one is refused and the right one then works |
| `three-wrong` | three wrong ones stop with the restart message, and Enter restarts |
| `no-disk` | no encrypted disk: it waits `rd.timeout`, says so, and offers a restart |
| `bad-root` | a good unlock but a bad `root=`: the error names the device |
| `tpm-without-token` | a TPM present but nothing enrolled: it says so and falls back to the passphrase |
| `enroll` | `systemd-cryptenroll` enrols a TPM2 + PIN and a recovery key from inside the guest (the one case that writes the disk) |
| `tpm-pin` | the PIN unlocks through the TPM token |
| `tpm-wrong-pin` | three wrong PINs, then it falls back and the passphrase works |
| `recovery-key` | the recovery key from `enroll` unlocks after the PIN is given up on |

A pass shows the logic, the TPM token with a software TPM, mounting and the handover. It doesn't cover the signed boot image, shim, Secure Boot and
PCR 7 on the real firmware, the real TPM, or the laptop's keyboard: those are the one-time boot on the laptop. The test boots the kernel directly
(no UEFI), with `console=ttyS0`, and the image built without root, so without the `/dev/console` node: the stricter case.

## Still to do

1. ✅ The qemu test passes.
2. ✅ `uki`, `entry` and `try` on the laptop: it booted.
3. ✅ The splash on a test boot (`autark.splash=1`, `quiet loglevel=3 vt.global_cursor_default=0`, on the test entry's command line only), and the PIN alone unlocking through the real TPM.
4. Boot the test entry a few more times, then make it the default only after it has booted reliably, and keep dracut as the hidden fallback ([roadmap](roadmap.md), M4).

## Open questions and risks

- **No udev.** Settled in qemu: `libdevmapper` creates `/dev/mapper/<name>` itself, so the image needs no udev.
- **Which error means "wrong PIN".** Seen with the software TPM: a wrong PIN is TPM error `0x98e` ("Bad PIN"), and a TPM in dictionary-attack lockout is `0x921`.
  Both are shown as "That PIN isn't right.", and the limit of three holds either way. A real TPM may word them differently.
- **USB keyboards.** The laptop's own keyboard (PS/2 `i8042`/`atkbd`), NVMe, ext4, dm-crypt and the TPM drivers are built into the kernel, so
  `autark-init` loads no modules. USB and I2C HID are modules, and `MODULE_SIG_FORCE` only accepts ones signed by the current key, so an
  external USB keyboard won't type the PIN until module loading is added (or those drivers are built in).
- **Secrets.** The PIN and passphrase are read without echo into a buffer that is wiped on drop; nothing secret is logged. libcryptsetup keeps
  its own copy while it works.
