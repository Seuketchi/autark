# Autark roadmap

Autark becomes a daily driver on the target laptop in about 7 months: May 2027 if work starts on Monday 2026-10-19 at roughly 10 hours a week. The start date isn't set yet. When it is, shift every date by the same amount.

There are two tracks. The **system track** is the LFS build, which Claude mostly runs. The **shell track** is the Rust code you write, and it can start on Ubuntu right away.

| # | Milestone | Track | Target | Done when | Needs |
| --- | --- | --- | --- | --- | --- |
| M0 | Host ready | System | 2026-10-25 | Step 0 on the target laptop: temporary Ubuntu at the end of the disk, Claude Code on your personal account, hardware profile committed to `hardware/target/`, version check passes | The target laptop |
| M1 | Bootable base | System | 2026-11-08 | Steps 1–7: an encrypted, hardened Autark boots from the target laptop's own disk, with your Secure Boot keys and TPM-plus-PIN unlock enrolled | M0 |
| M2 | Desktop | System | 2026-12-06 | Step 8: Wayfire, Wi-Fi, sound, Firefox and work tools run on Autark | M1 |
| M3 | Shell v1 | Shell | 2027-02-14 | Step 9, pieces 1–5: bar, dock, launcher, notification centre and lock screen, written in Rust and GTK4, run on Wayfire with nothing borrowed | Starts now on Ubuntu; moves to Autark after M2 |
| M4 | Rust initramfs | System | 2027-01-17 | `autark-init` unlocks the disk with TPM plus PIN and replaces dracut; dracut stays as a hidden fallback | M1 |
| M5 | Kith | Shell | 2027-04-18 | Kith runs standalone on the laptop (Hermes and Ollama): launcher actions, chat, approved memory, tasks and suggestions | M3 |
| M6 | Daily driver | System | 2027-05-16 | A full week on Autark with no fallback; then the temporary Ubuntu partition is deleted and Autark grows into its space | M2–M5 |
| M7 | Kith everywhere | Shell | When the box exists | Kith moves to your own box: reachable over Signal from the phone, laptop actions through MCP, Wren migrated and retired | M5, and a box with about 16 GB of RAM where only you have root |
| M8 | Notes v1 | Shell | 2027-03-14 | Autark Notes opens a vault with three panes, checklists, pins, live preview, `[[links]]`, backlinks, search, tags and graph view ([notes.md](notes.md)) | M3 |

After M6, maintenance takes a few hours a month: security advisories, kernel updates, and the yearly LFS releases ([build guide](build-guide.md)).

## Risks to the dates

- **The shell is the biggest unknown.** Its five pieces are new Rust and GTK4 code, and the lock screen is security-sensitive.
- **Long builds.** GCC's test suite, Firefox, Rust and Wine each take hours on this CPU. A failure late in a build costs a day.
- **Target hardware is still unknown.** Build time and the kernel config depend on its CPU, RAM and devices, which Step 0 captures.

## Open

- [ ] Start date for M0.
- [ ] Hardware for Kith's box (M7).
