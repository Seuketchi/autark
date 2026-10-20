# libXtst 1.2.6: X11 record and test extension library (libXtst.so.6). QtWebEngine links it.
# The sha256 is of x.org's release tarball, as downloaded 2026-10-20 (the publisher signs with PGP only).
name=libXtst
version=1.2.6
release=1
description="X11 record and test extension library"
source=(https://www.x.org/archive/individual/lib/libXtst-1.2.6.tar.xz)
checksums=(sha256:f94f0b37c07d80d877f3eda2c2405cc7e62aa9842f6310354aa349e3d66a4fe5)
depends=(glibc)
mode=staged

build() {
  ./configure --prefix=/usr --disable-static
  make
  make DESTDIR="$DESTDIR" install
}
