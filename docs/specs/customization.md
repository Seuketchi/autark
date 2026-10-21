# Customization

How people make Autark look and behave their way, and how others add to it without touching code. Written 2026-10-21; nothing in this document is built yet except where it says "today".

## Rules every setting follows

These are how Autark already works; the new settings keep to them.

1. **A setting is a file you can edit by hand.** `~/.config/autark/<name>.toml` replaces `/etc/autark/<name>.toml`; Settings edits the same file in place with `toml_edit`, so comments and unknown keys stay ([`autark-settings/src/config.rs`](https://github.com/Seuketchi/autark-tools/blob/main/crates/autark-settings/src/config.rs)). Wayfire's own options live in `~/.config/wayfire.ini`.
2. **Typos never break the desktop.** A file that fails to parse is reported and skipped, and the defaults are used. Unknown fields are rejected (`deny_unknown_fields`), so a misspelt key is an error you can see, not a silent no-op.
3. **Changes apply live.** The tools watch their files; Settings follows the file too, so an edit by hand shows in the pane.
4. **Defaults do not change.** A new setting starts at what Autark already does. Nobody's desktop looks different after an update they did not ask for.
5. **Everything can be undone.** Each pane gets "Reset to defaults", which removes the keys it owns and nothing else.
6. **Contributions are data first.** Looks, wallpapers and sounds are files in the repository, checked by CI, so a pull request does not need Rust.

## What exists today

| Setting | Where | Choices |
| --- | --- | --- |
| Theme | `theme.toml`, Settings → Appearance | light, dark, auto; 6 accents (`ACCENTS` in `theme.rs`); wallpaper; text size; font (Geist, Inter); reduce motion; high contrast |
| Wallpaper | `theme.toml` | 4 drawn scenes (`SCENES` in `wallpaper.rs`: sky, band, sun and hill colours) or a picture |
| Dock | `dock.toml`, Settings → Desktop & Dock | size, magnify, dots, position, auto-hide, pinned apps (file only: no pane for them) |
| Bar | `bar.toml` | clock format (a strftime string), battery percentage (file only: no pane) |
| Night light | `nightlight.toml` | schedule, warmth |
| Shortcuts | `~/.config/wayfire.ini` | listed read-only in `autark-keys`; edit the file by hand |
| Sounds | `sound.toml` | effects on or off; the two effects are synthesized in code, not files |
| Launcher | none | nothing configurable |

## 1. Looks

A **look** is a named bundle: colours, accent, wallpaper and font. Pick one in Appearance and the whole desktop changes; save your own and share the file.

- **File:** `/usr/share/autark/looks/<id>.toml` (shipped, from `config/looks/` in this repository) or `~/.config/autark/looks/<id>.toml` (yours). A look holds `name`, `author`, `licence`, `description`, an optional `mode` (light, dark, auto), `accent` (a name from `ACCENTS` or a hex colour), `wallpaper` (a scene id or a picture), `font`, and optional `[light]` and `[dark]` tables overriding any of the 20 palette tokens (`ground`, `surface`, `text`, `accent`…).
- **Applying it** writes the matching fields into `theme.toml` and records `look = "<id>"`; changing a field by hand afterwards shows the look as "Custom".
- **Code change:** `Palette::linen` builds colours from constants. It becomes a base palette plus overrides, so Linen stays the default and a look only lists what it changes.
- **UI:** a gallery of cards above Theme in Appearance, each drawn from the look's own colours (the way the Light and Dark cards are now); "Save current as look…" writes a file; "Custom accent" takes a hex colour.
- **Checks (CI, `scripts/ci/check-looks.py`):** the file parses; every colour is valid hex or `rgba()`; the licence is an SPDX id; and **text on surface, text on accent and text2 on surface meet WCAG AA contrast (4.5:1)** in each mode the look defines, so a look can be pretty but not unreadable. A look that fails does not merge.
- **Starter looks:** Linen (today's), Graphite, Midnight, Paper (high contrast), plus the six accents as one-click variants.

## 2. Keyboard shortcuts you can change

`autark-keys` lists what Wayfire is bound to. It becomes an editor.

- **Edit** a binding: select a row, press the new keys, confirm. The window asks Wayfire to stop handling shortcuts while it listens (the `shortcuts-inhibit` protocol; GTK's `inhibit_system_shortcuts`), so `Super+E` reaches the window instead of opening Files. Whether Wayfire's plugin honours this for every key is **the first thing to verify**; if not, capture falls back to "type the combination" as text.
- **Add** a command shortcut (name, command, keys) to the `[command]` section; **remove** or **reset** one to the shipped default.
- **Conflicts:** a combination already bound shows what has it and offers to swap or cancel, never silently takes it.
- **Writing:** a small line-based `.ini` editor in `autark-common` changes one value and leaves every other byte, comment and blank line as it was; Wayfire reloads its config on change. Writes go to a temporary file and are renamed over `wayfire.ini`, so a crash cannot leave half a file.
- **Tests:** round-trip an untouched file byte for byte; set, unset and add a key; conflict detection; refuse a value that is not a key combination.

## 3. Bar and dock layout

- **Bar:** `bar.toml` gains `items`, the order of what shows (`logo`, `app-name`, `spacer`, `kith`, `recording`, `notifications`, `volume`, `wifi`, `battery`, `clock`), so anything can be hidden or moved. Clock format becomes a choice (24-hour, 12-hour, with seconds, with date) with the strftime string still available under "Custom".
- **Dock:** the pane already covers size, magnify, dots, position and auto-hide. It gains **pinned apps**: a list built from the installed desktop files, reordered by dragging, with add and remove.
- **Both:** shown live in a small preview in the pane before they apply to the real bar.

## 4. Window feel

Wayfire has the plugins; Settings gets a **Windows** pane that edits `wayfire.ini` with the editor from section 2.

- **Animations:** `animate` style for open and close (none, zoom, fade, fire…) and speed. Reduce motion forces none.
- **Placement:** where a new window opens (`place`: centre, cascade, random, maximize).
- **Focus:** whether focus follows the pointer.
- **Blur:** off by default. The `blur` plugin costs GPU time, which matters on this laptop's integrated graphics; the pane says so beside the switch.
- **Not in this section, and why:** floating-window *gaps* do not exist in Wayfire; they come only with the `simple-tile` tiling plugin, which is a different way of working and would be its own, optional "Tiling mode". *Corner radius* is drawn by each application's own CSS, so a radius setting would be a theme token that Autark's tools follow and other apps ignore. Both are listed so the pane does not promise them.

## 5. Launcher and sounds

- **Launcher** gets its first config file, `launcher.toml`: which sources it searches (apps, files, calculator, actions, Kith), how many results, and whether it opens centred or at the top. Its shortcut is a Wayfire binding, so it is changed in section 2.
- **Sounds:** the two effects are synthesized today. A **sound set** is a folder of small audio files (`/usr/share/autark/sounds/<id>/`, each with a licence) mapped to events (notification, lock, unlock, screenshot, low battery). "Synthesized" stays the default set. CI checks that every file is short, small and licensed.

## 6. Wallpapers

- **Scenes become data.** A scene is a TOML file of colours (`sky`, `band`, `sun`, four `hills`), so a contributor adds a wallpaper by writing eight hex values, with no image and no licence question. The four built-in scenes move to `config/wallpapers/*.toml` unchanged.
- **Pictures** stay as they are. A **wallpaper folder** (a directory of images the user names) can rotate on a timer or at login; each image is a picture chosen by the user, so nothing is shipped.
- **Shipped images, if any:** each carries a sidecar `.toml` with author, SPDX licence and source; CI rejects an image over 1.5 MB or wider than 3840 px, so the repository stays small.

## Order of work

| # | What | Needs first | Why this place |
| --- | --- | --- | --- |
| 1 | Palette from base plus overrides; look files; the gallery; `check-looks.py` | nothing | Biggest visible change, and a contributor's first pull request |
| 2 | Wallpaper scenes as data | 1 (same CI pattern) | Cheap, and lets looks name a scene |
| 3 | The `.ini` editor in `autark-common`, then the shortcuts editor | nothing; the protocol check comes first | The most-wanted functional gap |
| 4 | Windows pane | 3 (the editor) | Reuses it |
| 5 | Bar items and the dock's pinned apps | nothing | Independent of the rest |
| 6 | Launcher config, sound sets | nothing | Last: smallest payoff |

Each step is its own pull request, with tests and (for the panes) a screenshot from the isolated demo session, and none changes anyone's defaults.

## Open questions

1. **Looks by name or by number?** Shipping ids like `graphite` is friendlier; a future "look store" would need unique author-prefixed ids. Start with plain names and revisit if the count passes a few dozen.
2. **Should a look be allowed to set the font?** Fonts have licences and must be installed; the look would name one and fall back to Geist when it is missing.
3. **Per-application overrides** (a dark terminal in a light desktop) are out of scope here.
