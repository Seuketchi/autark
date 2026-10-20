# libXScrnSaver 1.2.5: X11 screen saver extension library (libXss.so.1). Viber links it. The libX11 and libXext it builds on are not packages yet.
# The sha256 is of x.org's release tarball, as downloaded 2026-10-20 (the publisher signs with PGP only).
name=libXScrnSaver
version=1.2.5
release=1
description="X11 screen saver extension library"
source=(https://www.x.org/archive/individual/lib/libXScrnSaver-1.2.5.tar.xz)
checksums=(sha256:5057365f847253e0e275871441e10ff7846c8322a5d88e1e187d326de1cd8d00)
depends=(glibc)
mode=staged

build() {
  ./configure --prefix=/usr --disable-static
  make
  make DESTDIR="$DESTDIR" install
}
