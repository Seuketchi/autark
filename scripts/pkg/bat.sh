# bat 0.26.1: A cat clone with syntax highlighting
# Built from the crate crates.io publishes, with the Cargo.lock it ships and --locked, so every dependency crate is the
# one that lock file names and cargo checks it against the lock's sha256. The source's own sha256 below matches the
# checksum in the crates.io index (checked 2026-10-20); crates.io files are fetched at build time, so the build needs the network.
name=bat
version=0.26.1
release=1
description="A cat clone with syntax highlighting"
source=(bat-0.26.1.tar.gz::https://static.crates.io/crates/bat/bat-0.26.1.crate)
checksums=(sha256:cf66d0164db6827afe1694b8d4939f36a5507b7186f8d3cc529c66baf03b0d09)
depends=(glibc gcc)
mode=staged

build() {
  cargo build --release --locked
  install -Dm755 target/release/bat "$DESTDIR/usr/bin/bat"
  # build.rs writes the man page and completions into the build tree.
  out=$(ls -d target/release/build/bat-*/out | head -1)
  install -Dm644 "$out/assets/manual/bat.1" "$DESTDIR/usr/share/man/man1/bat.1"
  install -Dm644 "$out/assets/completions/bat.bash" "$DESTDIR/usr/share/bash-completion/completions/bat"
}
