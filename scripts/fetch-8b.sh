#!/bin/bash
# Phase 8b, part 0 (run on Ubuntu as yourself, with network; no root): download and verify every source in
# scripts/sources-8b.txt into sources-8b/, vendor the Rust crates the chroot build can't download, and pack the
# autark-tools workspace. Then run scripts/stage-8b.sh as root. Re-running skips what's already there and verified.
#
#   bash scripts/fetch-8b.sh                     # autark-tools from GitHub main
#   AUTARK_TOOLS=~/autark-tools bash scripts/fetch-8b.sh   # or from a local clone's HEAD
#
# Crates: scripts/vendor-crates.py checks each against its Cargo.lock's sha256 and writes per-file sha256s that
# cargo checks again at build time inside Autark. All crates go in one folder, crates-8b/ (cargo's directory
# source takes any mix of names and versions), packed as crates-8b.tar.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
out=$REPO/sources-8b
mkdir -p "$out"
cd "$out"

echo "== download and verify"
while read -r name url md5 sha256; do
  case "$name" in ''|'#'*) continue ;; esac
  if [ -e "$name" ] && echo "$sha256  $name" | sha256sum --quiet -c 2>/dev/null; then
    continue
  fi
  echo "   $name"
  curl -fsSL --retry 3 --proto '=https' -o "$name.part" "$url"
  if [ "$md5" != - ]; then
    echo "$md5  $name.part" | md5sum --quiet -c || { echo "$name: md5 mismatch"; exit 1; }
  fi
  echo "$sha256  $name.part" | sha256sum --quiet -c || { echo "$name: sha256 mismatch"; exit 1; }
  mv "$name.part" "$name"
done < "$REPO/scripts/sources-8b.txt"

echo "== autark-tools"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if [ -n "${AUTARK_TOOLS:-}" ]; then
  src=$AUTARK_TOOLS
else
  git clone -q --depth 1 https://github.com/Seuketchi/autark-tools.git "$work/autark-tools"
  src=$work/autark-tools
fi
commit=$(git -C "$src" rev-parse HEAD)
if [ "$(cat autark-tools.commit 2>/dev/null)" != "$commit" ]; then
  git -C "$src" archive --format=tar --prefix=autark-tools/ HEAD | gzip -n > autark-tools.tar.gz
  echo "$commit" > autark-tools.commit
fi
echo "   autark-tools at $commit"

echo "== vendor crates"
lock() {  # lock <tarball> <top folder>: the Cargo.lock inside a tarball
  tar -xzOf "$1" "$2/Cargo.lock" > "$work/$2.lock"
  echo "$work/$2.lock"
}
for pair in sudo-rs-0.2.15.tar.gz:sudo-rs-0.2.15 oo7-daemon-0.6.0.tar.gz:oo7-daemon-0.6.0 \
            oo7-pam-0.6.0.tar.gz:oo7-pam-0.6.0 autark-tools.tar.gz:autark-tools; do
  python3 -I "$REPO/scripts/vendor-crates.py" "$(lock "${pair%%:*}" "${pair#*:}")" "$out/crates-8b"
done
# Packed in a fixed order with fixed owners and times, so the same crates give the same tarball.
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 -cf crates-8b.tar crates-8b

echo "== checksum lists for the copy into Autark"
grep -v '^#' "$REPO/scripts/sources-8b.txt" | awk 'NF == 4 && $3 != "-" { print $3 "  " $1 }' > md5sums
{
  grep -v '^#' "$REPO/scripts/sources-8b.txt" | awk 'NF == 4 { print $4 "  " $1 }'
  sha256sum autark-tools.tar.gz crates-8b.tar
} > sha256sums
echo "== sources-8b ready: $(ls | wc -l) entries, $(du -sh . | cut -f1); next: sudo bash scripts/stage-8b.sh"
