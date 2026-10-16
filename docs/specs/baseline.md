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
