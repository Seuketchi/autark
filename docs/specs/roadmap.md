# Autark roadmap

Autark becomes a daily driver on the target laptop in about 7 months: May 2027 if work starts on Monday 2026-10-19 at roughly 10 hours a week. The start date isn't set yet. When it is, shift every date by the same amount.

There are two tracks. The **system track** is the LFS build, which Claude mostly runs. The **shell track** is the Rust code you write, and it can start on Ubuntu right away.

| # | Milestone | Track | Target | Done when | Needs |
| --- | --- | --- | --- | --- | --- |
| M0 ✅ (by 2026-10-17) | Host ready | System | 2026-10-25 | Step 0 on the target laptop: its existing Ubuntu as the build host, Claude Code on your personal account, hardware profile committed to `hardware/target/`, version check passes | The target laptop |
| M1 ✅ (2026-10-17) | Bootable base | System | 2026-11-08 | Steps 1–7: an encrypted, hardened Autark boots from the target laptop's own disk, with your Secure Boot keys and TPM-plus-PIN unlock enrolled | M0 |
| M2 ✅ (checked 2026-10-19) | Desktop | System | 2026-12-06 | Step 8: Wayfire, Wi-Fi, sound, Firefox and work tools run on Autark | M1 |
| M3 ✅ (checked 2026-10-19) | Shell v1 | Shell | 2027-02-14 | Step 9, pieces 1–5: bar, dock, launcher, notification centre and lock screen, written in Rust and GTK4, run on Wayfire with nothing borrowed | Starts now on Ubuntu; moves to Autark after M2 |
| M4 🔶 started | Rust initramfs | System | 2027-01-17 | `autark-init` unlocks the disk with TPM plus PIN and replaces dracut; dracut stays as a hidden fallback | M1 |
| M5 🔶 in progress | Kith | Shell | 2027-04-18 | Kith runs standalone on the laptop (Hermes and Ollama): launcher actions, chat, approved memory, tasks and suggestions | M3 |
| M6 | Daily driver | System | 2027-05-16 | A full week on Autark with no fallback; then decide what Ubuntu's space becomes (it sits before Autark's partitions, so `/home` can't simply grow into it) | M2–M5 |
| M7 | Kith everywhere | Shell | When the box exists | Kith moves to your own box: reachable over Signal from the phone, laptop actions through MCP, Wren migrated and retired | M5, and a box with about 16 GB of RAM where only you have root |
| M8 ✅ (checked 2026-10-19) | Notes v1 | Shell | 2027-03-14 | Autark Notes opens a vault with three panes, checklists, pins, live preview, `[[links]]`, backlinks, search, tags and graph view ([notes.md](notes.md)) | M3 |
| M9 ✅ (checked 2026-10-19) | System apps | Shell | 2027-06-13 | Files app, task manager with energy impact and force quit, widgets, and the `autark-stats` service ([decisions.md](decisions.md)) | M8 |
| M10 🔶 written, not run on Autark yet | Package manager | System | 2027-01-31 | `autark-pkg` installs, removes, upgrades and rolls back signed packages built from `scripts/pkg/`; the sandbox launcher runs a vendor binary under a Landlock profile | M2 |

## Status, checked 2026-10-19

✅ done, 🔶 started, ⬜ not started. "Checked" means the pieces were seen running on the target laptop that day.

- ✅ **M0.** M1 booted from the target laptop's own disk, so Step 0 is done.
- ✅ **M2.** Wayfire, Wi-Fi (iwd), sound (PipeWire), Firefox 158 (the default browser), the Web browser (Epiphany on WebKitGTK, phase 8c: kept installed but not used day to day, since it lacks accelerated video and WebRTC and each WebKit security fix means a rebuild), Node, git, curl, `gh` and Claude Code run. The desktop has a dark mode (`theme = "dark"` in `theme.toml`) that reaches the apps, the wallpaper, the terminal and the browser's pages (`ADW_DISABLE_PORTAL=1`, see the log).
- ✅ **M3.** The bar, dock, launcher, notification centre (`autark-notifyd`), lock screen (`autark-lock`) and power daemon (`autark-power`, started with the session since 2026-10-19) run. Still open: checking the lock screen's keyring unlock after the PAM-session change, and the autologin-then-lock flow (see the log).
- 🔶 **M4.** `autark-init` is written and its logic is tested (command line, unlock order and limits, and the real libcryptsetup on a LUKS2 image), and the initramfs image and the qemu tests with a software TPM pass (all 10 cases: unlock, retry, TPM plus PIN, recovery key, error cases, the hand-over). It has also booted the real laptop through a second boot entry (2026-10-20): the splash shows on the real screen, and the PIN alone unlocks the disk through the real TPM (this needed the OS-separator extend, see the init spec). What is left: boot it a few more times, then make it the default. See [autark-init.md](autark-init.md).
- 🔶 **M5.** `autark-ai` runs on Ollama: routing, ranking, the command check, chat, approved memory, tasks, suggestions and an MCP server. Not yet checked end to end against the "done when" line.
- ⬜ **M6.** Needs M4 and M5, and the Ubuntu and Windows retirement is blocked by the retire checklist (large photos still need a USB drive).
- ⬜ **M7.** No box yet.
- ✅ **M8.** Notes opens a vault with folders, tags, a note list, the editor, `[[links]]`, backlinks, search and a graph view.
- ✅ **M9.** Files, Activity (apps by CPU, memory, energy impact, disk and network, with force quit), the widgets and the `autark-stats` service run.
- 🔶 **M10.** `autark-pkg` (install, remove, upgrade, rollback, verify) and `autark-sandbox` are written. On Autark itself it hasn't run: the recipes aren't installed in the root-owned place it reads (`/usr/src/autark/scripts/pkg`) and there is no package database yet (`/var/lib/autark/pkg`). Without root it already works against a scratch folder (`search`, `info`, a dry-run install with dependencies, 149 recipes). [`scripts/autark-pkg-first-run.sh`](../../scripts/autark-pkg-first-run.sh), run once as root, installs the recipes, makes the signing key, imports the 278 file lists the phase scripts recorded, and shows what `upgrade` would change; it hasn't been run as root yet.

Beyond the milestones, also done and running: Settings (23 panes, with a root helper that needs its one-time install, `crates/autark-settings/data/install-helper.sh`), Terminal, the app icons, window buttons at the top right, the show-desktop command, and the dark mode.

After M6, maintenance takes a few hours a month: security advisories, kernel updates, and the yearly LFS releases ([build guide](build-guide.md)).

## Risks to the dates

- **The shell is the biggest unknown.** Its five pieces are new Rust and GTK4 code, and the lock screen is security-sensitive.
- **Long builds.** GCC's test suite, Firefox, Rust and Wine each take hours on this CPU. A failure late in a build costs a day.
- **Target hardware is still unknown.** Build time and the kernel config depend on its CPU, RAM and devices, which Step 0 captures.

## Open

- [ ] Start date for M0.
- [ ] Hardware for Kith's box (M7).
