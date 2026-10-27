# autoconf-archive 2024.10.16: hand-written. Arch's recipe also applies a patch fetched from cgit by commit id, whose bytes
# no longer match Arch's checksum (so the importer refuses it), and it fixes only the generated C++ standard detection of
# AX_CXX_COMPILE_STDCXX serial 21-23. The sha256 is Arch's, and is that of the tarball from ftpmirror.gnu.org.
name=autoconf-archive
version=2024.10.16
release=2
description="A collection of freely re-usable Autoconf macros"
source=(https://ftpmirror.gnu.org/autoconf-archive/autoconf-archive-2024.10.16.tar.xz)
checksums=(sha256:7bcd5d001916f3a50ed7436f4f700e3d2b1bade3ed803219c592d62502a57363)
depends=(autoconf)
mode=staged

build() {
./configure --prefix=/usr
make
make DESTDIR="$DESTDIR" install
rm -f "$DESTDIR/usr/share/info/dir"
}
