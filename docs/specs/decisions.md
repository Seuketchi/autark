# Autark decisions

Autark is a Linux From Scratch system, systemd edition, with a Mac-like desktop whose shell you write yourself. It is built on, and will replace the OS of, a second laptop, so the work laptop is never touched. Claude runs the build and you make every decision. Settled on 2026-10-16.

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

The **target laptop** is the standard. Its profile is captured in build guide Step 0 into [`hardware/target/`](../../hardware/target/), with `scripts/capture-hardware.sh`. The kernel config and firmware list come from there.

Until then, the work laptop's profile in [`hardware/work-laptop/`](../../hardware/work-laptop/) is the reference example:

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
| Platform | UEFI, Secure Boot on, TPM present | — |
| RAM | 30 GB | — |

## Decisions

| Area | Choice | Why |
| --- | --- | --- |
| Name | Autark | From *autarky*, meaning self-sufficient: a system that depends on no one |
| Base | Linux From Scratch, [systemd edition](https://www.linuxfromscratch.org/lfs/view/stable-systemd/) | Every package chosen and built from source |
| Init | systemd | Familiar from Ubuntu, and expected by desktop software |
| Root filesystem | ext4 | Supported by the book with no extra steps |
| Swap | zram, plus an optional swap file for hibernate | Compressed RAM swap suits a laptop |
| Disk encryption | The whole root disk (LUKS2), unlocked by the TPM chip plus a PIN, with a recovery key kept offline | Protects everything if the laptop is stolen |
| Bootloader | None: the firmware starts a signed unified kernel image directly, with the previous image as the fallback entry | The smallest attack surface, with nothing between the firmware and your signed kernel |
| Secure Boot | On, with your own keys (sbctl) | Only kernels you signed can boot |
| Initramfs | dracut for the first boot, then our own in Rust (`autark-init`) | We build our own code in Rust; the cryptography stays in libcryptsetup and tpm2-tss |
| Own code | Rust | Anything we write ourselves: shell, AI daemon, initramfs, tools |
| Package tracking | DESTDIR staging and file lists, from chapter 8 onward | So packages can be cleanly upgraded or removed later |
| Build host | The target laptop itself, from a temporary 60 GB Ubuntu partition at the end of its disk; Autark is built straight onto the rest | The work laptop stays untouched (no sudo rule, no CPU load), and the kernel is tuned to the hardware that runs Autark |
| Root access | Temporary passwordless sudo rule on the target laptop only, removed in Step 7 | Chapters 7 to 10 run as root in a chroot |
| Compositor | Wayfire | Stacking by design, with Mission Control–style and Spaces-style plugins and touchpad gestures |
| Desktop shell | Your own, written in GTK4 and Rust from scratch | A Mac feel from software you wrote, not substitutes |
| Day-one apps | A blank slate, with work tools added in Step 8 | Firefox, git, Node, Python, adb, Wine and the fingerprint driver come later |
| AI: fast decisions | Jev (TypeSafe), in the cloud | Typed decisions in about 150 ms for routing, urgency, safety and ranking. See [ai-layer.md](ai-layer.md) |
| AI: generation | Ollama, on the laptop | Private, works offline, and handles explanations and summaries |
| AI: defaults | Opt-in, with a local-only mode | Nothing goes to the cloud unless you turn it on |
| Logo | Loop: an "A" drawn as one closed stroke | Nothing borrowed |
| Assistant | **Kith**, with a Visor face: dark glass with glowing sage eyes | Old English for the people you know and trust: a companion, not a servant. Abstract face, never a human likeness |
| Assistant brain | Hermes on your own box (only you have root), Ollama on that box, Signal for the phone, Firecrawl self-hosted; Kith replaces Wren | One assistant and one memory on phone and laptop, without cloud models or unencrypted chat. All configurable for other setups |
| Login | Automatic login after the disk's TPM-plus-PIN unlock; the lock screen guards resume. A greeter (greetd plus our own Rust greeter) can be turned on for multi-user setups | The PIN at boot already proves it's you |
| Admin rights | sudo-rs | Same as sudo to use, without sudo's class of memory bugs |
| Terminal | foot | Writing a terminal is a large, security-sensitive job (escape sequences, Unicode, fonts); foot is the lightest Wayland terminal. Our own can come later |
| Files app | Our own in Rust, built right after Notes, which shares its file code | Matches the design; nothing borrowed in the shell |
| Code editor | Galley, your own IDE (Rust and Svelte), improved for Autark | Your own tool. As a webview app it needs WebKitGTK from BLFS |
| Command-line shell | bash | What LFS and all the build scripts use |
| System font | Geist and Geist Mono; Inter selectable in Settings | Used in the designs |
| Browser | Firefox with hardened defaults and uBlock Origin, all adjustable | Privacy without breaking sites |
| Backups | rustic (Rust, encrypted, restic-compatible) to an external drive, later also to Kith's box | Encryption protects the disk; only a backup protects the data |
| Kernel | The newest long-term-support kernel at build time | Longer security support and newer hardware drivers than the book's pinned version |
| LFS version | The stable release current on the start day, pinned and recorded in `log.md` | Rebuilds come out the same |
| Locale | en_US.UTF-8, time zone Asia/Manila, US keyboard | |
| Ollama model | llama3.2:3b; move to a 7–8B model only if the target measures at least 8 tokens per second | Usable speed on a CPU without a discrete GPU |
| Updates | Kith checks BLFS security advisories weekly; you apply updates by hand with per-package scripts until a Rust `autark-pkg` tool exists | Nothing updates silently |
| Disk layout (target) | EFI 1 GB, root A 80 GB, root B 80 GB (reserved for upgrades), encrypted `/home` with the rest, temporary Ubuntu 60 GB at the end | A/B upgrades need two roots; `/home` is shared by both and later grows into Ubuntu's space |
| DNS | DNS over TLS to Quad9 | Lookups encrypted; non-profit, no logs, blocks malware domains |
| Claude on the target | Claude Code with your personal Claude account | The company seat stays for company work |
| Maintenance | Security fixes within a week, other updates monthly, A/B rebuilds for major upgrades, a weekly Kith health report, package scripts in the repo. See [maintenance.md](maintenance.md) | Secure without surprises, and every change can be undone |
| Kernel driver coverage | Modules the target loads at capture time (with every device you own plugged in and used first), plus a baseline of common USB, storage, audio, video, Bluetooth and filesystem drivers as loadable modules | A device you plug in later still works |
| CPU microcode | Loaded first at boot, inside the signed kernel image | CPU security fixes (the Spectre family) |
| Firmware updates | fwupd with LVFS, applied by hand | Outdated BIOS, SSD or dock firmware is a security hole |
| Out-of-tree drivers | Only when the target's hardware needs one; signed with your module key and rebuilt by script on every kernel update | Signed-modules-only enforcement refuses anything unsigned |
| Graphics drivers | Open source only: Mesa iris/anv (Intel), radeonsi/radv (AMD), nouveau/NVK (NVIDIA) | No closed code in the kernel, and nothing to re-sign by hand |
| Peripherals in v1 | Bluetooth (BlueZ), webcams (V4L2, plus libcamera for newer Intel laptop cameras, through PipeWire), Android udev rules for adb. Printing (CUPS) later, optional | What a laptop needs day to day |
| Task manager | Our own in Rust and GTK4, like Activity Monitor: apps and processes with CPU, memory, disk, network and energy impact, plus a force-quit window (Ctrl+Alt+Esc). btop stays available in the terminal | Energy impact supports the efficiency goal |
| Resources day to day | A clean top bar, with meters as an option. Kith suggests quitting runaway apps (high CPU for minutes, or battery drain). Storage breakdown in Settings › About | Mac-like calm, without missing problems |
| Widgets | In the notification centre, plus optional desktop widgets. Version 1: calendar and clock, battery (including Bluetooth devices), resources, Kith's upcoming tasks and suggestions, a pinned note. Weather is opt-in, since it sends your location (Open-Meteo, no account) | Useful at a glance; nothing leaves the laptop by default |
| Widget sources | Only our own built-in Rust widgets in version 1; a sandboxed widget system can come later | No third-party code inside the shell |
| System metrics | One Rust service, `autark-stats`, shares metrics over D-Bus with the task manager, widgets and Kith; it polls only while something is displaying them | Gathered once, and battery saved when nobody's looking |
| Colour system | Linen (for now): warm whites #F6F4EF / #FFFFFF, text #24221E, sage accent #3F7A5F; dark-mode accent #7FC1A1 | Calm and light; white text on the accent stays readable |

## Rejected

- **Using REA (reverse engineering) on the kernel, Ubuntu or macOS:** everything open source is available as source. macOS's license bans reverse engineering, and nothing taken from it could ship.
- **Writing your own kernel:** it would mean writing every driver yourself, and it couldn't replace a daily system.
- **Remastering Ubuntu (Cubic, live-build):** not built from scratch.
- **Off-the-shelf shell pieces (Waybar, nwg-dock, Walker), Quickshell, AGS:** you'll write your own instead.
- **GRUB, systemd-boot:** they add code to the chain of trust that a firmware-started signed image doesn't need.
- **A custom bootloader, for now:** it mostly buys a boot menu, which is aesthetics. You can revisit it later as a small Rust project (the `uefi` crate).

## Open

- [ ] Build start date. You chose to start later.
- [ ] The target laptop: model, CPU, RAM, and what's on it now.
