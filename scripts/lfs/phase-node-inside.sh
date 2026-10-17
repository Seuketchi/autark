#!/bin/bash
# Node.js, curl and git, so Claude Code can run on Autark (installed afterwards with npm on the running system).
# Runs INSIDE the chroot as root, started by scripts/stage-node.sh (or ch7-chroot.sh with INSIDE=phase-node-inside.sh).
# BLFS 13.1-systemd commands; [Autark] marks deviations:
#   - Node.js uses its own bundled Brotli, c-ares, ICU, libuv, nghttp2 and simdutf instead of BLFS's six system
#     packages; system OpenSSL and zlib stay shared, as BLFS does.
#   - git without HTML/man docs (need asciidoc), no Rust parts (no rustc yet).
#   - libpsl's `meson setup` gets the `..` BLFS's command lacks.
# Sources: md5 from BLFS for all seven; Node's SHASUMS256.txt also GPG-verified (log.md, 2026-10-18).
set -euo pipefail

if [ ! -e /sources/wget-list-systemd ] || grep -qi ubuntu /etc/os-release 2>/dev/null; then
  echo "phase-node-inside.sh: not inside the Autark chroot; refusing to run" >&2
  exit 1
fi

logs=/sources/logs
mkdir -p "$logs" /sources/.done /sources/.track /var/lib/autark/files
srcdir=/sources
source "$(dirname "$0")/build-lib.sh"

export CFLAGS="-O2 -march=x86-64-v3 -pipe -fstack-protector-strong -fstack-clash-protection -fcf-protection=full -D_FORTIFY_SOURCE=3"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-Wl,-O1 -Wl,-z,relro -Wl,-z,now"

T_LIBUNISTRING=libunistring-1.4.2.tar.xz
T_LIBIDN2=libidn2-2.3.8.tar.gz
T_LIBPSL=libpsl-0.23.3.tar.gz
T_CURL=curl-8.21.0.tar.xz
T_GIT=git-2.55.0.tar.xz
T_WHICH=which-2.25.tar.gz
T_NODE=node-v24.19.0.tar.xz

testfail() { echo "== TESTFAIL: $*"; echo "$(date +%T) $*" >> "$logs/test-failures.txt"; }

# Names given on the command line restrict the run to those packages.
only=" $* "

snapshot() {
  find / -xdev \( -path /sources -o -path /tmp -o -path /root -o -path /var/lib/autark \) -prune \
    -o \( -type f -o -type l \) -print | LC_ALL=C sort
}

run_pkg() {
  local name=$1 tarball=$2 fn=$3
  if [ "$only" != "  " ]; then
    case "$only" in *" $name "*) ;; *) return ;; esac
  fi
  if [ -e "/sources/.done/node-$name" ]; then echo "== $name: already done, skipped"; return; fi
  snapshot > /sources/.track/before
  build "$tarball" "$fn"
  snapshot | LC_ALL=C comm -13 /sources/.track/before - > "/var/lib/autark/files/$name"
  echo "   $(wc -l < "/var/lib/autark/files/$name") new files tracked"
  touch "/sources/.done/node-$name"
}

pkg_libunistring() {
  ./configure --prefix=/usr    \
              --disable-static \
              --docdir=/usr/share/doc/libunistring-1.4.2
  make
  make install
}

pkg_libidn2() {
  ./configure --prefix=/usr --disable-static
  make
  make install
}

# [Autark] `..` added: BLFS's command runs meson in build/ without naming the source directory.
pkg_libpsl() {
  mkdir build
  cd    build
  meson setup .. --prefix=/usr --buildtype=release
  ninja
  { ninja test; } || testfail libpsl
  ninja install
}

# [Autark] Without the docs copy: the man pages are already installed, the rest is reference HTML.
pkg_curl() {
  ./configure --prefix=/usr    \
              --disable-static \
              --with-openssl   \
              --with-ca-path=/etc/ssl/certs
  make
  make install
}

# [Autark] No HTML/man docs (asciidoc and xmlto aren't installed). NO_RUST: git 2.55 builds Rust parts by default
# (cargo isn't installed until phase 8b); rebuild git with Rust once it is.
pkg_git() {
  ./configure --prefix=/usr                   \
              --with-gitconfig=/etc/gitconfig \
              --with-python=python3           \
              --with-libpcre2
  make NO_RUST=YesPlease
  make NO_RUST=YesPlease perllibdir=/usr/lib/perl5/5.44/site_perl install
}

pkg_which() {
  ./configure --prefix=/usr
  make
  make install
}

# [Autark] Bundled Brotli, c-ares, ICU (full), libuv, nghttp2, simdutf; shared OpenSSL and zlib as in BLFS.
pkg_node() {
  ./configure --prefix=/usr    \
              --shared-openssl \
              --shared-zlib
  make
  make install
}

run_pkg libunistring "$T_LIBUNISTRING" pkg_libunistring
run_pkg libidn2      "$T_LIBIDN2"      pkg_libidn2
run_pkg libpsl       "$T_LIBPSL"       pkg_libpsl
run_pkg curl         "$T_CURL"         pkg_curl
run_pkg git          "$T_GIT"          pkg_git
run_pkg which        "$T_WHICH"        pkg_which
run_pkg node         "$T_NODE"         pkg_node
echo "== node phase done: $(node --version 2>/dev/null), npm $(npm --version 2>/dev/null), $(git --version), $(curl --version | head -1 | cut -d' ' -f1-2)"
