# nspr 4.40: Netscape Portable Runtime, which NSS builds on. Viber's QtWebEngine links libnspr4, libplc4 and libplds4.
# The sha256 matches Mozilla's published SHA256SUMS for the release.
name=nspr
version=4.40
release=1
description="Netscape Portable Runtime"
source=(https://ftp.mozilla.org/pub/nspr/releases/v4.40/src/nspr-4.40.tar.gz)
checksums=(sha256:c0c1884c627f3db7a783f7c7314c695226b2043696791d15519e7e0578c19bdc)
depends=(glibc)
mode=staged

build() {
  cd nspr
  ./configure --prefix=/usr     \
              --with-mozilla    \
              --with-pthreads   \
              --enable-64bit
  make
  make DESTDIR="$DESTDIR" install
  rm "$DESTDIR"/usr/bin/{compile-et.pl,prerr.properties} "$DESTDIR"/usr/lib/*.a
}
