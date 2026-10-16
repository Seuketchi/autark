# Autark decisions

Autark is a Linux From Scratch system, systemd edition, with a Mac-like desktop whose shell you write yourself. It will replace the OS on a second laptop. Claude runs the build and you make every decision. Settled on 2026-10-16.

## Goals

Every decision is judged against these, in this order when they conflict:

1. **Security:** a small attack surface, hardened builds, and nothing running or listening that isn't needed.
2. **Efficiency:** low idle CPU and memory use, and long battery life.
3. **Performance:** fast boot, a responsive desktop, and builds tuned for this CPU.
4. **Aesthetics:** a Mac-like feel, built on top of the first three, never at their expense.

**Everything is configurable.** Each hardening, power and AI choice below is a secure default, not a lock. You can change it in Settings or in a plain config file under `/etc/autark/`, and per-package build flags can be overridden.

| Area | Default | Why |
| --- | --- | --- |
| CPU target | `-march=x86-64-v3 -O2` | Most of the speed gain, and still runs on any AVX2 CPU (about 2015 onward), including the second laptop |
| Build hardening | Stack protector (strong), `_FORTIFY_SOURCE=3`, stack-clash protection, CET (`-fcf-protection=full`), PIE, full RELRO, on every package | Blocks whole classes of exploits for roughly 1–3% performance |
| Kernel hardening | Lockdown, signed modules only, `init_on_alloc`, slab hardening, no kexec, unused subsystems removed | Small cost, and fits a kernel already trimmed to this hardware |
| Sandboxing | systemd sandboxing on every service, plus Landlock for apps | Built into the kernel and systemd, with no separate policy language to maintain alone |
| Network | Block all incoming connections (nftables), no services listening, DNS over TLS (systemd-resolved) | A laptop has no reason to accept incoming connections |
| Power | CPU energy setting switches automatically between battery and charger; device power saving tuned at boot | Battery life, measured with powertop rather than guessed |
| AI | Local-only (Ollama); Jev opt-in per feature | Text goes to the cloud only when you choose |

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
| AI: fast decisions | Jev (TypeSafe), in the cloud | Typed decisions in about 150 ms for routing, urgency, safety and ranking. See [ai-layer.md](ai-layer.md) |
| AI: generation | Ollama, on the laptop | Private, works offline, and handles explanations and summaries |
| AI: defaults | Opt-in, with a local-only mode | Nothing goes to the cloud unless you turn it on |
| Logo | Loop: an "A" drawn as one closed stroke | Nothing borrowed |

## Rejected

- **Using REA (reverse engineering) on the kernel, Ubuntu or macOS:** everything open source is available as source. macOS's license bans reverse engineering, and nothing taken from it could ship.
- **Writing your own kernel:** it would mean writing every driver yourself, and it couldn't replace a daily system.
- **Remastering Ubuntu (Cubic, live-build):** not built from scratch.
- **Off-the-shelf shell pieces (Waybar, nwg-dock, Walker), Quickshell, AGS:** you'll write your own instead.

## Open

- [ ] Build start date. You chose to start later.
