# eza 0.23.5: A modern replacement for ls
# Built from the crate crates.io publishes, with the Cargo.lock it ships and --locked, so every dependency crate is the
# one that lock file names and cargo checks it against the lock's sha256. The source's own sha256 below matches the
# checksum in the crates.io index (checked 2026-10-20); crates.io files are fetched at build time, so the build needs the network.
name=eza
version=0.23.5
release=1
description="A modern replacement for ls"
source=(eza-0.23.5.tar.gz::https://static.crates.io/crates/eza/eza-0.23.5.crate)
checksums=(sha256:334199a8059861f81a2d3d888a45f44fa55f82dade2412e752144a404d7ae9af)
depends=(glibc gcc)
mode=staged

build() {
  cargo build --release --locked
  install -Dm755 target/release/eza "$DESTDIR/usr/bin/eza"
  install -Dm644 completions/bash/eza "$DESTDIR/usr/share/bash-completion/completions/eza"
}
