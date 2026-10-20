# libcap-ng 0.9.6: OpenVPN 2.7 on Linux requires it. The source is GitHub's tag archive, which carries no configure, so autogen.sh runs first.
name=libcap-ng
version=0.9.6
release=1
description="Library for working with POSIX capabilities"
source=(libcap-ng-0.9.6.tar.gz::https://github.com/stevegrubb/libcap-ng/archive/refs/tags/v0.9.6.tar.gz)
checksums=(sha256:399040138e0ca62fa2bcabd63da9af4431a246ef7a654561a0ca3cb00010a539)
depends=(glibc autoconf automake libtool)
mode=staged

build() {
  ./autogen.sh
  ./configure --prefix=/usr    \
              --disable-static \
              --without-python3
  make
  make DESTDIR="$DESTDIR" install
}
