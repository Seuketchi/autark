# Autark decisions

Autark is a Linux From Scratch system, systemd edition, with a Mac-like desktop whose shell you write yourself. It will replace the OS on a second laptop. Claude runs the build and you make every decision. Settled on 2026-10-16.

## Hardware standard

This laptop is the reference machine. Its full profile is in [`hardware/`](../../hardware/).

| Part | Device | Firmware |
| --- | --- | --- |
| CPU | Intel Core i5-1135G7 (Tiger Lake), 8 threads | — |
| Graphics | Intel Iris Xe (8086:9a49) | `i915/tgl_dmc_ver2_12.bin` plus the tgl GuC/HuC files |
| Wi-Fi | Intel AX201 (8086:a0f0) | `iwlwifi-QuZ-a0-hr-b0-77.ucode` |
| Bluetooth | Intel (on the AX201) | `intel/ibt-19-0-4.sfi` |
| Audio | Tiger Lake SOF (8086:a0c8) | `intel/sof/sof-tgl.ri` plus its topology files |
| Ethernet | Intel I219-V (8086:15fc) | — |
| Storage | SanDisk/WD SN530 NVMe, behind Intel VMD | — (kernel needs `CONFIG_VMD=y`) |
| Fingerprint | ELAN 04f3:0c6c | Out-of-tree libfprint driver |
| Firmware | UEFI, Secure Boot on (to be turned off for Autark) | — |
| RAM | 30 GB | — |

## Decisions

| Area | Choice | Why |
| --- | --- | --- |
| Name | Autark | From *autarky*, meaning self-sufficient: a system that depends on no one |
| Base | Linux From Scratch, [systemd edition](https://www.linuxfromscratch.org/lfs/view/stable-systemd/) | Every package chosen and built from source |
| Init | systemd | Familiar from Ubuntu, and expected by desktop software |
| Root filesystem | ext4 | Supported by the book with no extra steps |
| Swap | zram, plus an optional swap file for hibernate | Compressed RAM swap suits a laptop |
| Bootloader | GRUB, UEFI, installed on the removable-media path | Covered step by step in the LFS and BLFS books |
| Secure Boot | Off on the target | Saves signing every kernel you build |
| Package tracking | DESTDIR staging and file lists, from chapter 8 onward | So packages can be cleanly upgraded or removed later |
| Build host | This laptop, into an 80 GB sparse disk image | Leaves your work system untouched |
| Root access | Temporary passwordless sudo rule, removed after the build | Chapters 7 to 10 run as root in a chroot |
| Compositor | Wayfire | Stacking by design, with Mission Control–style and Spaces-style plugins and touchpad gestures |
| Desktop shell | Your own, written in GTK4 and Rust from scratch | A Mac feel from software you wrote, not substitutes |
| Day-one apps | A blank slate, with work tools added in Step 8 | Firefox, git, Node, Python, adb, Wine and the fingerprint driver come later |

## Rejected

- **Using REA (reverse engineering) on the kernel, Ubuntu or macOS:** everything open source is available as source. macOS's license bans reverse engineering, and nothing taken from it could ship.
- **Writing your own kernel:** it would mean writing every driver yourself, and it couldn't replace a daily system.
- **Remastering Ubuntu (Cubic, live-build):** not built from scratch.
- **Off-the-shelf shell pieces (Waybar, nwg-dock, Walker), Quickshell, AGS:** you'll write your own instead.

## Open

- [ ] Build start date. You chose to start later.
