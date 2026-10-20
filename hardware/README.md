# Hardware profiles

Each folder is one laptop's profile, captured with `scripts/capture-hardware.sh <name>` on that laptop. The kernel config and firmware steps in the [build guide](../docs/specs/build-guide.md) read from `target/`.

| Folder | Laptop | Status |
| --- | --- | --- |
| `target/` | The laptop Autark is built on and runs on | Not captured yet (build guide Step 0) |
| `generic/` | Any other hardware: a broad kernel config, nothing trimmed | Kernel only; see its README |
| `work-laptop/` | The work laptop (i5-1135G7, Iris Xe, AX201) | Reference only; Autark is never built here |

Each profile holds `lscpu.txt`, `memory.txt`, `lspci.txt`, `lsusb.txt`, `lsmod.txt`, `disks.txt`, `kernel.config`, `platform.txt` (UEFI, Secure Boot, TPM) and `firmware.txt` (firmware files loaded at boot).

## Using a profile

`LFS=/mnt/lfs scripts/lfs/stage-profile.sh <profile>` copies the profile's kernel inputs into `$LFS/sources` for `scripts/lfs/ch10-kernel-inside.sh`:

- `kernel.config` is the starting config.
- `lsmod.txt` trims the kernel to the modules that machine loads. Add `--generic` (or leave `lsmod.txt` out) and every module of the starting config is built, which boots on hardware the profile never saw but takes longer.
- `kernel.fragment` (optional) lists options only that machine needs, in the format of `REQUIRED` in the kernel script.

Still tied to the `target` laptop and not yet profile-driven: the firmware files, CPU microcode and root LUKS UUID in `scripts/lfs/step6-boot-inside.sh`, and the `msi-*` and `nouveau-module.sh` scripts.
