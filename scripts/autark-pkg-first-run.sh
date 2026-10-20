#!/bin/sh
# First run of autark-pkg on Autark (roadmap M10). Run once, as root:
#   su -c 'sh scripts/autark-pkg-first-run.sh'   (from the repository's root)
# It does four things and says so:
#   1. copies the recipes (scripts/pkg) to /usr/src/autark/scripts/pkg, owned by root and writable by nobody else. autark-pkg runs
#      their scripts as root, so a folder a user could change would be a way to root; Settings' updates check refuses one.
#   2. makes the package signing key, if there isn't one (/etc/autark/pkg-secret.key, root only).
#   3. imports the file lists the phase scripts recorded in /var/lib/autark/files into the package database, so `autark-pkg list`,
#      `remove` and `upgrade` know what is installed. Only the database is written; no package file is touched.
#   4. shows what `autark-pkg upgrade` would change (a dry run, nothing is installed).
# ROOT=/some/folder runs the whole thing against that folder instead of / (for trying it; no root needed).
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
RECIPES_SRC=$HERE/pkg
ROOT=${ROOT:-}
PKG=${AUTARK_PKG:-autark-pkg}
DEST=$ROOT/usr/src/autark/scripts/pkg

die() { echo "autark-pkg-first-run.sh: $*" >&2; exit 1; }
[ -d "$RECIPES_SRC" ] || die "no recipes at $RECIPES_SRC"
if [ -z "$ROOT" ]; then
  [ "$(id -u)" = 0 ] || die "run it as root: su -c 'sh $0'"
  grep -q '^ID=autark' /etc/os-release || die "this is for Autark itself"
  pkg() { "$PKG" "$@"; }
else
  pkg() { "$PKG" --root "$ROOT" "$@"; }
fi

echo "== 1. recipes -> $DEST"
rm -rf "$DEST.new"
mkdir -p "$ROOT/usr/src/autark/scripts" "$DEST.new"
cp -R "$RECIPES_SRC/." "$DEST.new/"
if [ -z "$ROOT" ]; then
  chown -R root:root "$ROOT/usr/src/autark"
  chmod -R go-w "$ROOT/usr/src/autark"
  chmod 755 /usr/src /usr/src/autark /usr/src/autark/scripts
fi
rm -rf "$DEST.old"
[ ! -e "$DEST" ] || mv "$DEST" "$DEST.old"
mv "$DEST.new" "$DEST"
rm -rf "$DEST.old"
echo "   $(ls "$DEST" | grep -c '\.sh$') recipes"

echo "== 2. signing key"
if [ -e "$ROOT/etc/autark/pkg-secret.key" ]; then echo "   already there"; else pkg keygen; fi

echo "== 3. importing what the phase scripts installed"
mkdir -p "$ROOT/var/lib/autark/files"
pkg --recipes "$DEST" -n import | tail -3
pkg --recipes "$DEST" import | tail -1
echo "   $(pkg --recipes "$DEST" list | wc -l) packages in the database"

echo "== 4. what upgrade would change (a dry run)"
pkg --recipes "$DEST" -n upgrade || true
echo "done. Settings > Software Updates > Check for updates now works."
