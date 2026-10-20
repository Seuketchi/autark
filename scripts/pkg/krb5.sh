# krb5 1.22.2: Kerberos 5. Only the client libraries matter here (libgssapi_krb5.so.2, which Viber's bundled Qt Network
# links); the KDC, admin server, ksu (setuid) and the sample programs are removed after install. com_err and ss come from e2fsprogs.
# WARN_CFLAGS=-Wall replaces krb5's own warning flags, whose -Werror=discarded-qualifiers stops the build on glibc's
# const-correct strchr.
# PKINIT is off: its OpenSSL plugin doesn't build against OpenSSL 4, and the library needs no certificates here.
# The sha256 is of kerberos.org's tarball, as downloaded 2026-10-20 (MIT publishes a PGP signature, not a checksum).
name=krb5
version=1.22.2
release=1
description="Kerberos 5 client libraries and tools"
source=(https://kerberos.org/dist/krb5/1.22/krb5-1.22.2.tar.gz)
checksums=(sha256:3243ffbc8ea4d4ac22ddc7dd2a1dc54c57874c40648b60ff97009763554eaf13)
depends=(glibc e2fsprogs)
mode=staged

build() {
  cd src
  export WARN_CFLAGS=-Wall
  ./configure --prefix=/usr             \
              --sysconfdir=/etc         \
              --localstatedir=/var/lib  \
              --runstatedir=/run        \
              --with-system-et          \
              --with-system-ss          \
              --without-system-verto    \
              --without-ldap            \
              --without-tcl             \
              --disable-pkinit          \
              --disable-rpath
  make
  make DESTDIR="$DESTDIR" install
  # No servers, no setuid ksu, no sample clients.
  rm -r "$DESTDIR"/usr/sbin "$DESTDIR"/usr/share/examples
  rm "$DESTDIR"/usr/bin/{ksu,gss-client,uuclient,sim_client,sclient}
}
