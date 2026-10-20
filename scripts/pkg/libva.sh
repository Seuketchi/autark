# libva 2.24.1: Video Acceleration API (libva.so.2, libva-drm.so.2, libva-x11.so.2). Viber's bundled ffmpeg links all three.
# DRM and X11 backends on, Wayland and GLX off. The sha256 is of the GitHub release tarball, as downloaded 2026-10-20.
name=libva
version=2.24.1
release=1
description="Video Acceleration API"
source=(https://github.com/intel/libva/releases/download/2.24.1/libva-2.24.1.tar.bz2)
checksums=(sha256:eec6050b52876f229bd35e9df17cd31a06785e18e6f7990c445b584628483d67)
depends=(glibc libdrm)
mode=staged

build() {
  mkdir build
  cd    build
  meson setup ..               \
        --prefix=/usr          \
        --buildtype=release    \
        -D with_x11=yes        \
        -D with_glx=no         \
        -D with_wayland=no
  ninja
  DESTDIR="$DESTDIR" ninja install
}
