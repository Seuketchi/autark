# Autark maintenance

Autark stays secure with a weekly check and a monthly update session, and every change can be undone. Major upgrades are rebuilt alongside the running system, never on top of it. Expect a few hours a month. Settled on 2026-10-16.

## Cadence

| What | When | How |
| --- | --- | --- |
| Security fixes | Within a week of a matching [BLFS advisory](https://www.linuxfromscratch.org/blfs/advisories/) | Rebuild the affected package with its script; reboot only if it's the kernel or a core library |
| Everything else | One monthly batch | Rebuild changed packages, then reboot once for a new kernel |
| Major upgrades | Each new LFS release you choose to adopt, about once a year | A/B rebuild (below) |
| Health report | Weekly, from Kith | A task notification (below) |
| Firmware and microcode | Checked in the monthly batch | `fwupd` for BIOS, SSD and dock firmware; microcode updates arrive with linux-firmware and Intel's microcode releases |
| Out-of-tree drivers | On every kernel update | Their `kmod-<name>.sh` scripts rebuild and sign them before the reboot |

Nothing updates itself. Kith reports, you decide, and the scripts (later `autark-pkg`) do the work.

## Undo

- **Packages:** the last two builds of every package are kept as archives in `/var/cache/autark/pkgs/`. Rolling back means reinstalling the older archive, using the package's file list to remove the newer one cleanly.
- **Kernel:** the previous signed kernel image stays as the "Autark (previous)" boot entry.
- **Data:** a rustic backup runs at the start of every update session.

## Major upgrades: A/B roots

The disk has two root partitions, A and B, and a separate encrypted `/home` that both share.

1. While running A, build the new LFS release into B, using the package scripts.
2. Copy `/etc` changes over, and sign B's kernel image.
3. Add a boot entry for B and reboot into it. A stays untouched as the fallback.
4. After a week without problems, B becomes the main system, and A becomes the target of the next upgrade.

## Weekly health report

A Kith task every Monday, delivered as a notification:

- Advisories that match installed package versions.
- Failed systemd services since the last report.
- Disk health (SMART or NVMe health log) and free space.
- Battery health (design capacity versus current full charge).
- How long ago the last backup ran, and whether it succeeded.

## Rebuild knowledge lives in the repo

- **Package scripts:** every package has `scripts/pkg/<name>.sh`, holding its version, source checksum, configure flags, DESTDIR install and file list. It's committed with every change.
- **The log:** `log.md` records why anything differs from the book.
- **The result:** a rebuild, whether for an A/B upgrade or after a disaster, is a replay of scripts rather than a memory test.
