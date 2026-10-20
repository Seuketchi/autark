# atuin 18.24.1: Shell history in a searchable database
# Built from the crate crates.io publishes, with the Cargo.lock it ships and --locked, so every dependency crate is the
# one that lock file names and cargo checks it against the lock's sha256. The source's own sha256 below matches the
# checksum in the crates.io index (checked 2026-10-20); crates.io files are fetched at build time, so the build needs the network.
name=atuin
version=18.24.1
release=1
description="Shell history in a searchable database"
source=(atuin-18.24.1.tar.gz::https://static.crates.io/crates/atuin/atuin-18.24.1.crate)
checksums=(sha256:bc51cac15d024125d53398cb94ff2c5346e9453e0827e19c927106fa5dd03c11)
depends=(glibc gcc)
mode=staged

build() {
  cargo build --release --locked
  install -Dm755 target/release/atuin "$DESTDIR/usr/bin/atuin"
  install -d "$DESTDIR/usr/share/bash-completion/completions"
  target/release/atuin gen-completions --shell bash > "$DESTDIR/usr/share/bash-completion/completions/atuin"
}
