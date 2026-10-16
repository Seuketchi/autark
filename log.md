# Autark build log

Every package built, every change made, every error. Enough to repeat the build without Claude.

## 2026-10-16 — Step 0 (target laptop: MSI Cyborg 15 A13UCK)

- Host: Ubuntu 26.04 LTS, kernel 7.0.0-34. LFS book: 13.1-systemd.
- Repo cloned to `~/personal/autark` (build guide says `~/autark`; same repo, different path).
- Hardware profile captured to `hardware/target/` (not yet re-run with all devices plugged in).
  `firmware.txt` has only 6 entries: the kernel log needs `adm` group or sudo to read fully.
- Hardware differs from the reference: i5-13420H (Raptor Lake), 24 GB, Intel UHD + NVIDIA RTX 3050 (hybrid).
- Disk: single 512 GB NVMe. Windows 11 (185 GB) at the front, Ubuntu (290 GB) at the end, 100 MB ESP.
  Partitioning (Step 1) is on hold: the 100 MB ESP can't hold two UKIs, and Step 0's layout would wipe this Ubuntu.
- `version-check.sh` (from chapter 2.2): 20 OK. Errors: bison, gawk, m4, texinfo missing; `/bin/sh` is dash.
- Installed bison, gawk, m4, texinfo, cryptsetup, qemu-system-x86, ovmf.
- `/bin/sh` → bash. On Ubuntu 26.04 (dash 0.5.12) `dpkg-reconfigure dash` no longer works: dash ships
  `/usr/bin/sh` itself and the debconf answer is ignored. Done instead with a local diversion, which survives dash updates:
  `dpkg-divert --local --add --rename --divert /usr/bin/sh.dash /usr/bin/sh && ln -s bash /usr/bin/sh`.
  Undo: `rm /usr/bin/sh && dpkg-divert --remove --rename /usr/bin/sh`.
- No terminal in Claude Code's `!` prompt, so `sudo` can't ask for a password there; `pkexec` (desktop password dialog) works.
- `version-check.sh`: all OK, 12 cores.
- Freed 32 GB of caches (Gradle, pip, Chrome, JetBrains, Dart). Plan changed: build into an image file first,
  test in qemu, shrink Ubuntu and move to a partition only once it boots.
