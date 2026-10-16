# Autark

A Linux distribution built from scratch: Linux From Scratch (systemd edition) as the base, Wayfire as the compositor, and a Mac-like desktop shell written in GTK4 and Rust.

The name comes from *autarky*, meaning self-sufficient: every package chosen and built from source, every decision made by its owner.

## Layout

| Path | What |
| --- | --- |
| [`docs/specs/decisions.md`](docs/specs/decisions.md) | What Autark is made of and why, plus the hardware standard |
| [`docs/specs/build-guide.md`](docs/specs/build-guide.md) | The build, step by step, from an Ubuntu host to a running desktop |
| [`hardware/`](hardware/) | Reference laptop profile: kernel config, loaded modules, PCI and USB devices |

The disk image, source tarballs and backups stay local and are never committed (see `.gitignore`).

## Status

The specs are settled. The build hasn't started yet.
