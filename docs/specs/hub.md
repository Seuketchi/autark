# Autark Hub

A native window to find, install, update and remove software on Autark, with every download checked. It is the "easily install software" answer for a distribution whose software list is short on purpose and grows through pull requests. Written 2026-10-21; nothing is built yet.

The Hub is a face on `autark-pkg`, not a second package manager. It owns no install logic, no signature logic and no repository format; if it can't be done from the command line, the Hub can't do it either.

## Goals and non-goals

| Goal | Non-goal |
| --- | --- |
| Install, update, remove and roll back a package in a few clicks, no terminal | Replacing `autark-pkg` or `autark-install` |
| Show where each package comes from and whether it is verified | Updating the base system image or the kernel (a later question) |
| Make a contributed recipe reach users quickly, with a clear signed path | Hosting binaries (GitHub releases do, see [releasing.md](releasing.md)) |
| Work offline for what is already installed | Telemetry, accounts, ratings, an "app store" economy |

The name is a working one. `autark-launcher` is already the Spotlight-style launcher, so this is `autark-hub` (app id `org.autark.Hub`), shown in the launcher and dock as **Software**.

## Where packages come from

| Source | What it is | Trust | Shown as |
| --- | --- | --- | --- |
| **Prebuilt** | A signed archive in the `packages-<N>` release, listed in the signed `index` | Signed by the release key, checked by `autark-pkg` against `/etc/autark/pkg-keys/` | *Verified* |
| **Build from source** | A hand-written recipe in `scripts/pkg/` with no prebuilt archive yet | The recipe is reviewed in a pull request; the build runs here, then is signed by this machine's key | *Reviewed recipe*, with "takes about N minutes" |
| **Imported from Arch** | A recipe `autark-pkg arch` makes from the Arch package | Nobody on Autark has reviewed it | *Unreviewed*, asks before it continues, as `autark-pkg` does today |

The default list shows only Prebuilt and Reviewed. Imported packages appear only after a search that finds nothing else, or with the "Include Arch packages" switch.

## How a contribution reaches the Hub

1. Someone opens a pull request adding `scripts/pkg/<name>.sh`. CI checks the header, the checksums and that `build()` downloads nothing ([CONTRIBUTING.md](../../CONTRIBUTING.md)); the maintainer reviews and merges.
2. At the next release the maintainer builds it and runs `autark-pkg publish` with the offline release key. The archive and a new signed `index` go into `packages-<N>`.
3. The package shows up as *Verified* in the Hub for everyone, with no release of the Hub itself.

Until step 2, the package is *Reviewed recipe* and can be built locally. The slow step is the human holding the release key; that is deliberate, and automating it would mean a signing key on a server.

## Screens

```
┌──────────────────────────────────────────────────────────────┐
│ Software                        [ Search …                 ]  │
├───────────┬──────────────────────────────────────────────────┤
│ Browse    │  Firefox                       ● Verified        │
│ Installed │  Web browser                   130.0-1  64 MB     │
│ Updates 3 │  [ Install ]   Source: packages-3 · sha256 ab12… │
│           ├──────────────────────────────────────────────────┤
│           │  Depends on: gtk3, nss, alsa-lib  (2 to install) │
└───────────┴──────────────────────────────────────────────────┘
```

- **Browse**: search and categories. A row shows name, one-line description, version, size and the source badge.
- **Installed**: everything `autark-pkg list` shows, with Remove and, where a second build is kept, Roll back. A package another one depends on says so and cannot be removed.
- **Updates**: what `autark-pkg upgrade` would change, one by one or all, with version before and after.
- **Details**: description, version, size, dependencies that would be pulled in, files it would own, source and signature state, and what changed since the installed version.
- **Progress**: download, verify, install, with the log one click away. A failed step says which one and leaves the system as it was.

## How it works

- **Reading** the catalogue: the repository's signed `index` for what is prebuilt, the recipe headers in the `recipes` folder from `/etc/autark/pkg.toml` (`/usr/src/autark/scripts/pkg` by default) for names, descriptions and dependencies, and `/var/lib/autark/pkg` for what is installed. Whether a fresh install ships that recipes folder is unchecked; if it does not, the installer or the first index fetch has to provide it. All read-only, no privileges.
- **Changing** the system: the Hub runs `autark-pkg install|remove|upgrade|rollback` as root through a small helper, the way Settings does ([`autark-settings-helper`](https://github.com/Seuketchi/autark-tools/tree/main/crates/autark-settings) behind `sudo`, with the password kept in memory for five minutes and never written). The helper accepts only those four verbs and package names that exist in the catalogue; it never takes a URL, a path or a shell string.
- **Verification** stays in `autark-pkg`: it refuses an archive not signed by a key in `/etc/autark/pkg-keys/`, or one that is not the name and version asked for. The Hub shows the result and adds nothing to it.
- **Language**: Rust and GTK4 like the rest of the shell, a new crate `autark-hub` in `autark-tools`.

## What `autark-pkg` needs first

These are gaps today, in order of what blocks the Hub:

1. **Read the index.** `autark-pkg` looks up a prebuilt archive by name and version and never reads `index`. It needs a command that fetches `index` and `index.minisig`, verifies it against the trusted keys, and prints what it lists (`autark-pkg catalog`).
2. **Descriptions in the index.** An index line is `name version sha256 size file`. The Hub needs a description and a category too; either extend the line (and version the format) or publish a second signed file. Recipes already have `description=`.
3. **Machine-readable output** (`--json`) for `search`, `info`, `list`, the pending upgrades, and progress events, so the Hub does not scrape text.
4. **One install transaction with progress**, and a clear exit code per failure (offline, bad signature, missing dependency, build failed).
5. **A library crate.** Moving `autark-pkg` logic into a library lets the Hub read the database directly; until then it shells out.

## Security

- The Hub never downloads, unpacks or runs anything itself. It only asks `autark-pkg`.
- A freshly installed Autark trusts the release key only. The Hub shows the repository address from `/etc/autark/pkg.toml` and offers no way to add a key or a repository from the window.
- *Unreviewed* packages always show a warning and ask before the build starts.
- No analytics, no phoning home. The only network use is the repository and, for imports, Arch Linux, both visible in Details.
- The helper's four verbs and its argument checks get tests, and changes to it need the maintainer's review ([CODEOWNERS](../../.github/CODEOWNERS)).

## Phases

| Phase | Delivers | Needs |
| --- | --- | --- |
| 0 | Read-only: Installed list and Details from the local database and recipes | Nothing new |
| 1 | Install, remove and roll back from local recipes, with progress and the root helper | Gaps 3 and 4 |
| 2 | Browse and Updates from the signed index: the *Verified* path | Gaps 1 and 2, the release key, a published `packages-<N>` |
| 3 | Self-update through the same path, release notes in Details, base-system updates (separate spec) | Phase 2 |

Phase 2 is blocked on the release key being made: until `autark-pkg release-keygen` has been run on offline media and the first signed packages are published, there is nothing *Verified* to show.

## Open questions

1. **Name in the UI**: "Software" or "Hub"?
2. **Prebuilt for which CPU?** Recipes build with `-march=x86-64-v3`; the Hub should refuse a prebuilt archive on a CPU without it, and say so.
3. **How many builds does the maintainer sign per release?** Hand-signing a new package each time is fine for dozens, not hundreds. A second, lower-trust "community" key could cover the long tail; it widens what a stolen key can do, so it needs its own spec first.
4. **Vendor binaries** (Chrome, Postman, Viber): a Hub entry that installs a sandboxed launcher profile (`autark-sandbox`) rather than a source recipe. Not specified yet.
