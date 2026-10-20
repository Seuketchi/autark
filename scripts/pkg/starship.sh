# starship 1.27.0: Cross-shell prompt
# Built from the crate crates.io publishes, with the Cargo.lock it ships and --locked, so every dependency crate is the
# one that lock file names and cargo checks it against the lock's sha256. The source's own sha256 below matches the
# checksum in the crates.io index (checked 2026-10-20); crates.io files are fetched at build time, so the build needs the network.
name=starship
version=1.27.0
release=1
description="Cross-shell prompt"
source=(starship-1.27.0.tar.gz::https://static.crates.io/crates/starship/starship-1.27.0.crate)
checksums=(sha256:34cf67d88d9f637a5e235f11e2cd3678350e20fa840cf2559fc72c4e025cb8a9)
depends=(glibc gcc)
mode=staged

build() {
  cargo build --release --locked
  install -Dm755 target/release/starship "$DESTDIR/usr/bin/starship"
  install -d "$DESTDIR/usr/share/bash-completion/completions"
  target/release/starship completions bash > "$DESTDIR/usr/share/bash-completion/completions/starship"
}
