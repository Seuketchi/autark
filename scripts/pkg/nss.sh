# nss 3.131: Network Security Services. Viber's QtWebEngine links libnss3, libnssutil3 and libsmime3.
# Built with the system zlib and SQLite; the sha256 matches Mozilla's published SHA256SUMS for the release.
# NSS_ENABLE_WERROR=0 because the book's warnings-as-errors build breaks with newer compilers; the gtests are not built.
name=nss
version=3.131
release=1
description="Network Security Services"
source=(https://ftp.mozilla.org/pub/security/nss/releases/NSS_3_131_RTM/src/nss-3.131.tar.gz)
checksums=(sha256:ca0005bc77e9255d9942103e6f9756cfe311a3df72afa99860709e386eb3c167)
depends=(glibc nspr sqlite zlib)
mode=staged

build() {
  cd nss
  make BUILD_OPT=1                         \
       NSPR_INCLUDE_DIR=/usr/include/nspr  \
       USE_SYSTEM_ZLIB=1 ZLIB_LIBS=-lz     \
       NSS_ENABLE_WERROR=0                 \
       NSS_USE_SYSTEM_SQLITE=1             \
       NSS_DISABLE_GTESTS=1                \
       USE_64=1

  cd ../dist
  for lib in freebl3 freeblpriv3 nss3 nssckbi nssdbm3 nssutil3 smime3 softokn3 ssl3 nsssysinit; do
    install -vDm755 Linux*/lib/lib$lib.so -t "$DESTDIR"/usr/lib
  done
  install -vDm644 Linux*/lib/*.chk -t "$DESTDIR"/usr/lib
  install -vdm755 "$DESTDIR"/usr/include/nss
  cp -RL {public,private}/nss/* "$DESTDIR"/usr/include/nss
  chmod 644 "$DESTDIR"/usr/include/nss/*
  install -vDm755 Linux*/bin/{certutil,pk12util} -t "$DESTDIR"/usr/bin

  # The makefiles don't make nss.pc; this is pkg/pkg-config/nss.pc.in filled in.
  install -vdm755 "$DESTDIR"/usr/lib/pkgconfig
  cat > "$DESTDIR"/usr/lib/pkgconfig/nss.pc << EOF
prefix=/usr
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include/nss

Name: NSS
Description: Network Security Services
Version: $version
Requires: nspr >= 4.40
Libs: -L\${libdir} -lssl3 -lsmime3 -lnss3 -lnssutil3
Cflags: -I\${includedir}
EOF
}
