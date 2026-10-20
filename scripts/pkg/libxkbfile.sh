# libxkbfile 1.2.0: X11 keyboard file library (libxkbfile.so.1). QtWebEngine links it.
# The sha256 is of x.org's release tarball, as downloaded 2026-10-20 (the publisher signs with PGP only).
name=libxkbfile
version=1.2.0
release=1
description="X11 keyboard file library"
source=(https://www.x.org/archive/individual/lib/libxkbfile-1.2.0.tar.xz)
checksums=(sha256:7f71884e5faf56fb0e823f3848599cf9b5a9afce51c90982baeb64f635233ebf)
depends=(glibc)
mode=staged

build() {
  mkdir build
  cd    build
  meson setup ..             \
        --prefix=/usr        \
        --buildtype=release
  ninja
  DESTDIR="$DESTDIR" ninja install
}
