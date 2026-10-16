# Autark

A Linux distribution built from scratch for security, efficiency and performance first, with a Mac-like desktop on top: Linux From Scratch (systemd edition) as the base, Wayfire as the compositor, a desktop shell written in GTK4 and Rust, and an AI layer (Jev and Ollama).

The name comes from *autarky*, meaning self-sufficient: every package chosen and built from source, every decision made by its owner.

## Layout

| Path | What |
| --- | --- |
| [`docs/specs/decisions.md`](docs/specs/decisions.md) | What Autark is made of and why, plus the hardware standard |
| [`docs/specs/build-guide.md`](docs/specs/build-guide.md) | The build, step by step, from an Ubuntu host to a running desktop |
| [`docs/specs/roadmap.md`](docs/specs/roadmap.md) | Milestones and target dates, from host setup to daily driver |
| [`docs/specs/notes.md`](docs/specs/notes.md) | Autark Notes: Apple Notes feel, Obsidian files, links and graph |
| [`docs/specs/ai-layer.md`](docs/specs/ai-layer.md) | AI in the OS: Jev for fast decisions, Ollama for local generation |
| [`design/`](design/) | Desktop design mockups: every screen, Kith, icons, logo and colours |
| [`hardware/`](hardware/) | Laptop profiles (kernel config, modules, devices, firmware): `target/` once captured, `work-laptop/` as reference |
| [`scripts/`](scripts/) | `capture-hardware.sh`, which records a laptop's profile |

The disk image, source tarballs and backups stay local and are never committed (see `.gitignore`).

## Status

The specs are settled. The build hasn't started yet; see the [roadmap](docs/specs/roadmap.md).
