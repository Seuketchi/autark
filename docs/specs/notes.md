# Autark Notes

Autark Notes looks like Apple Notes and works like Obsidian underneath. Every note is a plain Markdown file, and links between notes are first-class, including a graph view. It's written in Rust with GTK4, like the rest of the shell. Settled on 2026-10-16.

## Decisions

| Area | Choice | Why |
| --- | --- | --- |
| Build or adopt | Our own, in Rust and GTK4 | Small scope; follows the rule that our own code is Rust; shares the shell's look and Kith's hooks |
| Storage | Plain Markdown files in any folder you open (a vault) | Works alongside Obsidian, git and the `lattice` repo; nothing locked in; backups are just files on the encrypted disk |
| Feel | Apple Notes on the surface, Obsidian underneath | Simple day to day, powerful when you need it |
| Kith access | Off by default; allowed per folder, read-only; Kith edits a note only when asked in that turn | Private notes stay private |

## Version 1

- **Apple Notes surface:** three panes (folders, a note list with previews, the editor), checklists, and pinned notes.
- **Notepad basics:** open and save, tabs, and find and replace.
- **Obsidian underneath:** live Markdown preview as you type, `[[links]]` with backlinks, a quick switcher, full-text search, tags, and a **graph view** of how notes link.

Later: plugins, and sync (git handles sync better than a custom engine).

## Files

- A vault is any folder. Folders in the sidebar are folders on disk.
- Pins and window state live in a hidden `.autark-notes/` folder inside the vault, so the Markdown stays clean.
- Links use Obsidian's `[[note name]]` syntax, so an Obsidian vault opens unchanged.
