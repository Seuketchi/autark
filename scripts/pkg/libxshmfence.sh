# libxshmfence 1.3.3: X11 shared memory fence library (libxshmfence.so.1). QtWebEngine links it.
# The sha256 is of x.org's release tarball, as downloaded 2026-10-20 (the publisher signs with PGP only).
name=libxshmfence
version=1.3.3
release=1
description="X11 shared memory fence library"
source=(https://www.x.org/archive/individual/lib/libxshmfence-1.3.3.tar.xz)
checksums=(sha256:d4a4df096aba96fea02c029ee3a44e11a47eb7f7213c1a729be83e85ec3fde10)
depends=(glibc)
mode=staged

build() {
  ./configure --prefix=/usr --disable-static
  make
  make DESTDIR="$DESTDIR" install
}
