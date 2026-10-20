# Releasing

How a release is made and signed, so other people can install Autark without compiling it ([installer.md](installer.md)). Today it is done by hand on the build machine; nothing here is automated yet.

## The release key

Releases are signed with their own key, never with the key the build machine signs its packages with. A stolen build machine must not be able to sign a release.

- Made once, on a machine you trust: `autark-pkg release-keygen /media/usb/release`. It asks for a password and writes `autark-release.key` (the secret, password-protected) and `autark-release.pub`.
- The secret key lives on offline media (an encrypted USB stick), with a second copy somewhere else. Losing it means every user has to be given a new public key by some other route; leaking it means the same. Write the password down separately.
- The public key is committed to the repository (`config/pkg-keys/autark-release.pub`, to be added) and shipped in the rootfs in `/etc/autark/pkg-keys/`, so a fresh install trusts releases and nothing else.

## Making a release

1. Build the packages from a clean checkout on the build machine (`autark-pkg install` or `build` for each recipe), so the cache holds the current version of everything the rootfs contains.
2. Make the rootfs from that system: `sudo scripts/make-rootfs.sh --src <mounted root> --version <N> --out release/` (see [installer.md](installer.md)). It refuses to pack anything with keys, users or passwords left in it.
3. Sign the packages with the release key, mounted for the occasion: `autark-pkg publish release/packages --key /media/usb/release/autark-release.key`. This re-signs copies of the newest cached builds and writes the signed `index`.
4. Sign the rootfs tarball the same way (`minisign -S -s /media/usb/release/autark-release.key -m release/autark-rootfs-<N>.tar.zst`) and keep its `SHA256SUMS`.
5. Unmount and put the stick away. Upload `release/` (below).

## Where it lives

GitHub releases on this repository: one release per version tag, `release-<N>`, holding the rootfs, its signature and checksums, and the installer image (`autark-installer-<N>.img`). The package repository is a second release, `packages-<N>`, holding every package archive with its `.minisig` and the `index` (about two files per package, well inside GitHub's limit of 1000 assets per release). A system uses it with
`repo = "https://github.com/Seuketchi/autark/releases/download/packages-<N>"` in `/etc/autark/pkg.toml`.

The format is just files in a folder, so any static web server can host the same layout later; moving hosts means changing that line.

## What a user checks

`autark-pkg` downloads nothing it does not verify: each archive must be signed by a key in `/etc/autark/pkg-keys/` and be the package and version it asked for. The installer checks the rootfs signature against the same key before it unpacks anything.
