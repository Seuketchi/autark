# Hardware profiles

Each folder is one laptop's profile, captured with `scripts/capture-hardware.sh <name>` on that laptop. The kernel config and firmware steps in the [build guide](../docs/specs/build-guide.md) read from `target/`.

| Folder | Laptop | Status |
| --- | --- | --- |
| `target/` | The laptop Autark is built on and runs on | Not captured yet (build guide Step 0) |
| `generic/` | Any other hardware: a broad kernel config, nothing trimmed | Kernel only; see its README |
| `work-laptop/` | The work laptop (i5-1135G7, Iris Xe, AX201) | Reference only; Autark is never built here |

Each profile holds `lscpu.txt`, `memory.txt`, `lspci.txt`, `lsusb.txt`, `lsmod.txt`, `disks.txt`, `kernel.config`, `platform.txt` (UEFI, Secure Boot, TPM) and `firmware.txt` (firmware files loaded at boot).

## Using a profile

`LFS=/mnt/lfs scripts/lfs/stage-profile.sh <profile> --luks-uuid <uuid>` copies the profile's inputs into `$LFS/sources` for the kernel script (`ch10-kernel-inside.sh`) and the boot script (`step6-boot-inside.sh`):

- `kernel.config` is the starting config.
- `lsmod.txt` trims the kernel to the modules that machine loads.
- `kernel.fragment` (optional) lists options only that machine needs, in the format of `REQUIRED` in the kernel script.
- `firmware.list` (optional) is the firmware files that machine loads, one pattern per line, relative to the linux-firmware tree.
- `boot.env` (optional) sets `CPU_UCODE`, the one Intel microcode file for its CPU.
- `--luks-uuid` is the UUID of the encrypted root. It belongs to one installed disk, so it is never kept in a profile.

`--generic` leaves out `lsmod.txt`, `kernel.fragment`, `firmware.list` and `boot.env`: the kernel keeps every module, all of linux-firmware is installed, and the early microcode image carries every Intel and AMD file, so the same build boots on hardware the profile never saw. It's larger and slower to build.

Still tied to the `target` laptop: the `msi-*` and `nouveau-module.sh` scripts, and the Secure Boot enrolment through Ubuntu's shim in Step 7b.
