# openssl 3.5.9 (the 3.5 long-term release), shared libraries only: libssl.so.3 and libcrypto.so.3.
# Autark's openssl is 4.x (libssl.so.4) and Viber's bundled Qt Network is built against the 3 series. The sonames
# differ, so both sit side by side. Only the two libraries are installed: no headers, programs or modules, which
# stay with openssl. OPENSSLDIR points at a directory that doesn't exist, so this copy never reads /etc/ssl/openssl.cnf,
# which is written for 4.x. The sha256 matches the one OpenSSL publishes next to the tarball.
name=openssl3-libs
version=3.5.9
release=1
description="OpenSSL 3.5 shared libraries (for programs built against the 3 series)"
source=(https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz)
checksums=(sha256:603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a)
depends=(glibc zlib)
mode=staged

build() {
  ./config --prefix=/usr                  \
           --openssldir=/usr/lib/openssl3 \
           --libdir=lib                   \
           shared zlib-dynamic            \
           no-legacy no-module no-tests
  make build_libs
  install -vDm755 libssl.so.3 libcrypto.so.3 -t "$DESTDIR"/usr/lib
}
