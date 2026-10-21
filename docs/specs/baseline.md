# Ubuntu baseline

Autark has to beat today's Ubuntu setup on the work laptop, measured on 2026-10-16 (Ubuntu 26.04, i5-1135G7, 30 GB RAM). Each problem has a fix for Ubuntu now and Autark's answer.

| Area | Ubuntu now | Fix on Ubuntu now | Autark's answer |
| --- | --- | --- | --- |
| Open ports | SSH (`ssh.socket`) on port 22 and an iperf3 server on port 5201 accept connections from any network; mDNS and several UDP ports open | Disable `iperf3` and `ssh.socket`; turn on the firewall with incoming connections blocked | No services listening; nftables blocks all incoming connections |
| Always-on services | 37 running | Remove what isn't used | Only what's needed, each sandboxed by systemd |
| Boot time | 28.4 s: firmware 12.4 s, GRUB 2.9 s, initramfs 2.4 s, userspace 10.1 s (6.0 s of it waiting for the network) | Disable `NetworkManager-wait-online`; try the firmware's fast-boot setting | No bootloader (firmware starts the signed kernel), nothing waits for the network, our own small Rust initramfs |
| Boot errors | 103 error lines in one boot: ACPI firmware warnings, Bluetooth hands-free noise, VPN failing to resolve its server, `tern-pull` failures | Make `tern-pull` treat a failed GitHub call as a skip, not a failure | Kith's weekly health report lists failed services and errors |
| Fingerprint | apt upgrades of `libfprint-2-2` silently replace the out-of-tree ELAN driver | Hold the package (`apt-mark hold libfprint-2-2`); rebuild with `~/.local/src/reinstall-fingerprint-driver.sh` when you choose to update | The driver is built as an Autark package with its own recipe, so updates rebuild it instead of breaking it |
| Packages | 2,039 debs plus 12 snaps | Remove snaps you don't use | Every package chosen and built from source; no snaps |
| CPU at idle | `kitchend` (Agent Kitchen) at about 42% CPU while the desktop is otherwise quiet | Profile `kitchend` for a busy loop | `autark-stats` shows energy impact per app; Kith flags runaway apps |
| Memory | 13 GB in use (Chrome, Claude Code, `kitchend`) | | zram swap; lighter shell; measured with `autark-stats` |
| Battery | 86% of design capacity | | Power profiles switch automatically; health tracked in the weekly report |

## Not fixable by the OS

- **Firmware boot time (12.4 s):** set in the laptop's firmware. Disabling unused boot devices and enabling fast boot may help.
- **ACPI warnings:** bugs in the laptop's firmware tables. Harmless, but they show up in every boot log.

## How Autark is measured

The same numbers are re-measured on the target laptop once Autark runs: boot time (`systemd-analyze`), open ports (`ss -tulpn`), running services, errors per boot, idle CPU and memory, and idle power draw on battery.

## Autark measured

Measured on 2026-10-21 on the target laptop (MSI Cyborg 15, 24 GB RAM) while it was in normal use: one reading each, so treat them as rough. Ubuntu was measured on a **different** laptop (the work one, above), so only the numbers that don't depend on the hardware are compared.

| Area | Ubuntu (work laptop) | Autark (target laptop) | Comparable? |
| --- | --- | --- | --- |
| Reachable from the network | SSH on 22 and iperf3 on 5201 accepted connections from any network | None: nftables drops all incoming connections with no exceptions. `sshd` still listens on 22, but the firewall blocks it | Yes |
| Running services | 37 | 19 | Yes, loosely (different software installed) |
| Error lines in one boot | 103 | 23 (kernel messages such as a Bluetooth firmware error and "TDX not supported") | Loosely: different firmware and drivers |
| Packages | 2,039 debs and 12 snaps | 278 base packages tracked by the build scripts and 189 managed by `autark-pkg` (the two sets may overlap) | Loosely: different scope |
| Boot, userspace only | 10.1 s (6.0 s waiting for the network) | 4.9 s to the graphical target, nothing waits for the network | Loosely: the CPU and disks differ |
| Boot, firmware | 12.4 s | 13.1 s | No: it's the laptop's firmware |
| Boot, kernel and initramfs | 2.4 s | 22.2 s, which includes the time spent typing the disk passphrase | No |
| Idle memory and CPU | 13 GB in use, one service at 42% CPU | 11 GB in use with a virtual machine and a browser open, 6% CPU busy | No: not an idle measurement on either |
| Battery health | 86% of design | 75% of design | No: different batteries |

Not measured yet: idle power draw on battery, battery life, and a clean idle memory reading after boot with nothing else open.
