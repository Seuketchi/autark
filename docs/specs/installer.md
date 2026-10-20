# Installer design

Step 2 of making Autark installable by someone else ([open-source goal](../autark-opensource-checklist.md)). Today Autark is built by hand on the laptop it runs on, into a disk image that is copied over (build guide, Steps 1 to 7). This document describes how a stranger gets the same result on their machine without building Linux From Scratch. Nothing here exists yet.

## Goals

- Boot a USB stick, answer a few questions, and end with an encrypted, Secure Boot, TPM-unlocked Autark like the one on the author's laptop.
- Every key, passphrase and disk ID is made on the machine being installed. Nothing personal ships in the release.
- Never touch a partition the user did not pick. Windows or another Linux next to it must survive.
- Testable end to end in qemu (UEFI firmware plus a virtual TPM), so a second laptop is not needed to know it works.

Not goals for the first version: BIOS (non-UEFI) boot, dual-booting with Autark's own bootloader menu (the firmware's boot menu is enough), RAID/LVM, non-x86.

## Release artifacts

Built once per release on a build machine, signed with the project's key, and published:

| Artifact | What it is |
| --- | --- |
| `autark-rootfs-<version>.tar.zst` | The finished system as files: LFS base, generic kernel and modules (`stage-profile.sh generic`), all firmware and microcode, desktop and tools, and the `autark-pkg` database. No keys, no machine-id, no fstab/crypttab, no boot image. |
| Package repository | Signed `.tar.zst` packages for every recipe, so a user installs and upgrades without compiling (`autark-pkg` reads the project's public key from the rootfs). |
| `autark-<version>.iso` | A small live system that runs the installer and carries the rootfs tarball. |
| `SHA256SUMS` + signature | For the above. |

The kernel's module-signing key is the build machine's, so modules built after the release (out-of-tree drivers such as `msi-ec`) cannot load under `MODULE_SIG_FORCE`. They have to be built into the release or into the kernel package, and kernel updates arrive from the repository as packages.

## What the installer does

1. **Check the machine.** UEFI mode, Secure Boot state, TPM 2.0 present, RAM and disk size. Say plainly what is missing: no TPM means passphrase-only unlock, not a failed install.
2. **Choose where.** List the disks and their partitions. The user picks a blank disk by typing its name; show exactly what will be created and erased, and require typing the disk name to confirm. Layout: ESP (1 GiB), root and `/home`, with sizes scaled to the disk. Version 1 has no root B (the A/B update slot in [maintenance.md](maintenance.md)), and works on a blank disk only.
3. **Choose secrets.** Disk passphrase, TPM PIN, user name and password, hostname. Typed into the installer's own prompt, never passed as an argument or logged.
4. **Format.** LUKS2 on root A and `/home`, ext4 inside, FAT32 on the ESP. The UUIDs are new, so nothing in the rootfs can know them in advance.
5. **Unpack** the rootfs tarball (checksum and signature checked first) onto the new root.
6. **Make the machine-specific files** inside the new root: `/etc/fstab`, `/etc/crypttab`, hostname, machine-id, the user, `/etc/kernel/cmdline` with the new LUKS UUID.
7. **Make the boot keys.** A new Secure Boot db key on the encrypted root (as `step_secureboot_key` does today), then the initramfs (dracut, not host-only) and the signed unified kernel image with `ukify`.
8. **Enrol.** Secure Boot: if the firmware is in Setup Mode, enrol the new db key directly; otherwise install shim and enrol the key through the MOK manager at the next boot (what Step 7b does today). TPM: `systemd-cryptenroll` binds the unlock to the PCRs and the PIN; a recovery key is generated and shown once, to be written down.
9. **Boot entries.** `efibootmgr` entries for "Autark" and "Autark (previous)", and the removable path `EFI/BOOT/BOOTX64.EFI`, as in Step 7b.
10. **Finish.** Unmount, print the recovery key and what to do on the first boot, reboot.

An installer failure before step 4 leaves the disk untouched. After it, the half-made partitions can be removed by running the installer again on the same space.

## Pieces to write

- `autark-install`, a root-only program in the live ISO. A Rust binary fits the rest of the project, but the first version can be a shell script that wraps `sfdisk`, `cryptsetup`, `ukify` and `systemd-cryptenroll`, as the current build scripts do. It should keep every step idempotent and have a `--dry-run` that prints the plan without changing anything.
- The rootfs and ISO builders, run on the build machine from the finished LFS system. These replace the dd copy in Step 7b.
- A repository publisher: sign the packages, write the index, upload.
- An installer test: qemu with OVMF (Secure Boot variables), an emulated NVMe disk and a software TPM (`swtpm`), booting the ISO, running the installer unattended, then booting the result and checking that it unlocks.

## Decisions for the first version

Settled 2026-10-20; each can be revisited once something works.

1. **Hosting:** GitHub releases for the rootfs, ISO and package repository. A mirror comes later. The signing key is the project's, kept offline, and its public half ships in the rootfs.
2. **Root slots:** a single root. The installer leaves room to add root B later, but does not create it.
3. **Interface:** text mode. A graphical installer comes after the base works.
4. **Disks:** a blank disk only. Installing into free space beside other systems comes later, because it is where data loss happens.

## Order of work

1. Rootfs tarball builder and a generic-profile build (needs the build machine to rebuild the kernel with `stage-profile.sh generic`).
2. `autark-install` against a blank qemu disk, without Secure Boot or the TPM; then add each.
3. The package repository and `autark-pkg` pointing at it.
4. ISO builder, then the full qemu test, then a real second machine.
