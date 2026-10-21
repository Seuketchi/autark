# Autark

A Linux distribution built from scratch for security, efficiency and performance first, with a Mac-like desktop on top: Linux From Scratch (systemd edition) as the base, Wayfire as the compositor, a desktop shell written in GTK4 and Rust, and an AI layer (Jev and Ollama).

The name comes from *autarky*, meaning self-sufficient: every package chosen and built from source, every decision made by its owner.

## Layout

| Path | What |
| --- | --- |
| [`docs/specs/decisions.md`](docs/specs/decisions.md) | What Autark is made of and why, plus the hardware standard |
| [`docs/specs/build-guide.md`](docs/specs/build-guide.md) | The build, step by step, from an Ubuntu host to a running desktop |
| [`docs/specs/installer.md`](docs/specs/installer.md) | The installer: what it does, the release files, installing from a USB stick or Ventoy |
| [`docs/specs/releasing.md`](docs/specs/releasing.md) | How a release is made and signed |
| [`docs/specs/baseline.md`](docs/specs/baseline.md) | Today's Ubuntu measured, with fixes and Autark's target for each problem |
| [`docs/specs/maintenance.md`](docs/specs/maintenance.md) | Updates, rollback, A/B upgrades, health checks |
| [`docs/specs/roadmap.md`](docs/specs/roadmap.md) | Milestones and target dates, from host setup to daily driver |
| [`docs/specs/notes.md`](docs/specs/notes.md) | Autark Notes: Apple Notes feel, Obsidian files, links and graph |
| [`docs/specs/ai-layer.md`](docs/specs/ai-layer.md) | AI in the OS: Jev for fast decisions, Ollama for local generation |
| [`design/`](design/) | Desktop design mockups: every screen, Kith, icons, logo and colours |
| [`hardware/`](hardware/) | Laptop profiles (kernel config, modules, devices, firmware): `target/` once captured, `work-laptop/` as reference |
| [`scripts/`](scripts/) | The build scripts (`lfs/`), package recipes (`pkg/`), the installer (`autark-install.sh`) and the release builders (`make-rootfs.sh`, `make-installer-image.sh`) |

The disk image, source tarballs and backups stay local and are never committed (see `.gitignore`).

The Rust tools (shell, Kith's daemon, Notes, Files, the package manager and more) live in a separate repo, [`autark-tools`](https://github.com/Seuketchi/autark-tools), so other distros can use them too.

## Status

Experimental. Autark runs daily on its author's laptop (an MSI Cyborg 15), built by hand following the build guide. The installer works from start to finish in a virtual machine: it erases a blank disk, makes an encrypted install and the machine's own Secure Boot key, and the result boots and logs in. It has not been tried on a second real machine yet.

What is still manual or missing:

- Secure Boot enrolment and TPM unlock are separate steps after the install (see [installer.md](docs/specs/installer.md)).
- There is no signed release yet, so there are no downloads: the rootfs and installer image are built from source (`scripts/make-rootfs.sh`, `scripts/make-installer-image.sh`).
- The kernel and some scripts are tuned for the author's laptop; `hardware/generic/` is the profile for other hardware and is largely untested.

The installer erases a whole disk and asks you to type its name first. Don't try it on a machine whose data you care about.

## Licence

Autark's own code, scripts and documents are licensed under either of [Apache License 2.0](LICENSE-APACHE) or [MIT licence](LICENSE-MIT), at your option. The software the recipes in `scripts/pkg/` build keeps its own licences.
