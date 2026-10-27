# python-libxml2 2.15.3: the Python module of libxml2, which the base libxml2 is built without. It is built from the same
# source and only the module is packaged: itstool and other programs import libxml2.
name=python-libxml2
version=2.15.3
release=1
description="Python bindings of libxml2"
source=(https://download.gnome.org/sources/libxml2/2.15/libxml2-2.15.3.tar.xz)
checksums=(md5:b7b0123654f86ebf630a5cbedaafdece)
depends=(libxml2 python)
mode=staged

build() {
  sed -i "/'git'/,+3d" meson.build
  mkdir build
  cd    build
  meson setup ..            \
        --prefix=/usr       \
        --buildtype=release \
        -D history=enabled  \
        -D icu=disabled     \
        -D python=enabled
  ninja
  mkdir -p "$DESTDIR/staging"
  DESTDIR="$DESTDIR/staging" ninja install
  mkdir -p "$DESTDIR/usr/lib"
  mv "$DESTDIR/staging/usr/lib/python"* "$DESTDIR/usr/lib/"
  rm -rf "$DESTDIR/staging"
}
