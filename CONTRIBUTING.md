# Contributing to Autark

Pull requests are welcome: software, hardware fixes, polish and docs. `main` is protected, so nothing lands without a
pull request, passing checks and the maintainer's review. Nothing here is automated onto people's machines: a release is
cut and signed by hand ([`docs/specs/releasing.md`](docs/specs/releasing.md)).

## The short version

1. Fork, branch, change one thing.
2. Run the checks below that apply.
3. Open a pull request and say what you tested and on which hardware.

## Adding software (a package recipe)

One file, `scripts/pkg/<name>.sh`; the format is in [`scripts/pkg/README.md`](scripts/pkg/README.md). Rules:

- Sources over `https`, and a `sha256:` checksum for each (older recipes still carry `md5:`; new ones may not).
- No network access, `curl | sh`, or prebuilt binaries in `build()`: it compiles the source named in `source=`.
- Say in the pull request how you built and ran it. A package you cannot run is not ready.
- Software that only ships a vendor binary goes through the sandbox launcher (`autark-sandbox`), not a recipe.

Check it before you push:

```sh
python3 -I scripts/ci/check-recipes.py --strict <name>.sh
```

## Other changes

```sh
python3 -I scripts/ci/check-recipes.py     # every recipe still parses
scripts/ci/check-secrets.sh                # no keys, tokens or logins are committed
for f in $(git ls-files '*.sh'); do bash -n "$f"; done
```

Code for the desktop and the tools lives in [`autark-tools`](https://github.com/Seuketchi/autark-tools).

## What review looks at

- **Risk first.** Anything touching disks, boot, keys, the installer, signing or the firewall gets a slower, closer
  review, and a test on a real machine or in qemu (`scripts/qemu-test/`).
- **Small and reversible.** A change that can be rolled back (`autark-pkg rollback`) merges faster.
- **Hardware reports help.** `scripts/capture-hardware.sh <name>` records a laptop's profile.

## Security

Never commit keys, passwords or logins; CI refuses them. To report a vulnerability, do not open a public issue: use
GitHub's "Report a vulnerability" on the Security tab once it is enabled, or write to the maintainer privately.

By contributing you agree your work is licensed MIT OR Apache-2.0, like the rest of the project.
