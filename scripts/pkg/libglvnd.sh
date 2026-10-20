# libglvnd 1.7.0: the vendor-neutral GL dispatch layer: libGL, libGLX, libOpenGL, libEGL, libGLESv1_CM and libGLESv2.
# Programs link these (Viber's bundled Qt6 needs libOpenGL and libGLX, and crashes without a glvnd-aware Mesa), and glvnd
# passes their calls to the driver Mesa installs as libEGL_mesa.so.0 (mesa.sh builds with glvnd=enabled). It takes over
# libEGL.so.1 and the GLES libraries and headers that Mesa used to install itself, so install it together with mesa.
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
        -D egl=true          \
        -D gles1=true        \
        -D gles2=true
  ninja
  DESTDIR="$DESTDIR" ninja install
}
