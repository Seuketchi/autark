# Hardware profiles

Each folder is one laptop's profile, captured with `scripts/capture-hardware.sh <name>` on that laptop. The kernel config and firmware steps in the [build guide](../docs/specs/build-guide.md) read from `target/`.

| Folder | Laptop | Status |
| --- | --- | --- |
| `target/` | The laptop Autark is built on and runs on | Not captured yet (build guide Step 0) |
| `work-laptop/` | The work laptop (i5-1135G7, Iris Xe, AX201) | Reference only; Autark is never built here |

Each profile holds `lscpu.txt`, `memory.txt`, `lspci.txt`, `lsusb.txt`, `lsmod.txt`, `disks.txt`, `kernel.config`, `platform.txt` (UEFI, Secure Boot, TPM) and `firmware.txt` (firmware files loaded at boot).
