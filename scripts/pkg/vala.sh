# vala 0.56.19: hand-written. Vala is written in Vala: the git tag archive that Arch's recipe turns into needs a valac to start
# from, and the release tarball carries the generated C. The sha256 is the one published beside it on download.gnome.org.
name=vala
version=0.56.19
release=4
description="Compiler for the GObject type system"
source=(https://download.gnome.org/sources/vala/0.56/vala-0.56.19.tar.xz)
checksums=(sha256:5ad7cbbfcc0de61b403d6797c9ef60455bfbebd8e162aec33b5b0b097adfb9d5)
depends=(glib graphviz)
mode=staged

build() {
./configure --prefix=/usr
make
make DESTDIR="$DESTDIR" install
}
