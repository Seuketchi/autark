# libglvnd 1.7.0: libGL, libGLX and libOpenGL for programs that link them (Viber, Qt). EGL and GLES stay with Mesa
# (Mesa installs those libraries itself), so this package carries only the GL/GLX dispatch libraries. Its headers and
# pkg-config files are dropped: Mesa owns /usr/include/GL and KHR, and nothing here builds against libGL.
# The sha256 is of GitLab's tag archive, as downloaded 2026-10-20.
name=libglvnd
version=1.7.0
release=1
description="GL and GLX dispatch libraries"
source=(https://gitlab.freedesktop.org/glvnd/libglvnd/-/archive/v1.7.0/libglvnd-v1.7.0.tar.gz)
checksums=(sha256:2b6e15b06aafb4c0b6e2348124808cbd9b291c647299eaaba2e3202f51ff2f3d)
depends=(glibc)
mode=staged

build() {
  mkdir build
  cd    build
  meson setup ..             \
        --prefix=/usr        \
        --buildtype=release  \
        -D egl=false         \
        -D gles1=false       \
        -D gles2=false
  ninja
  DESTDIR="$DESTDIR" ninja install
  rm -r "$DESTDIR"/usr/include "$DESTDIR"/usr/lib/pkgconfig
}
