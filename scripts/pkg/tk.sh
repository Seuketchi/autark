# tk 8.6.17: hand-written. Arch's tk is 9.0, which needs Tcl 9; the Tcl here is 8.6 (LFS), so the 8.6 series of Tk goes with it.
# The sha256 is of the sourceforge release tarball as downloaded over https.
name=tk
version=8.6.17
release=1
description="A windowing toolkit for use with tcl"
source=(tk8.6.17-src.tar.gz::https://downloads.sourceforge.net/tcl/tk8.6.17-src.tar.gz)
checksums=(sha256:e4982df6f969c08bf9dd858a6891059b4a3f50dc6c87c10abadbbe2fc4838946)
depends=(tcl libx11 libxft fontconfig)
mode=staged

build() {
SRCDIR=$(pwd)
cd unix
./configure --prefix=/usr --mandir=/usr/share/man --enable-threads --enable-64bit --with-tcl=/usr/lib
make
make DESTDIR="$DESTDIR" install install-private-headers
ln -sf wish8.6 "$DESTDIR/usr/bin/wish"
sed -e "s|$SRCDIR/unix|/usr/lib|" -e "s|$SRCDIR|/usr/include|" -i "$DESTDIR/usr/lib/tkConfig.sh"
}
