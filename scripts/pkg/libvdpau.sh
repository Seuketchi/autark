# libvdpau 1.5: Video Decode and Presentation API for Unix (libvdpau.so.1). Viber's bundled ffmpeg (libavutil) links it.
# Documentation and the DRI2 backend are off. The sha256 is of GitLab's tag archive, as downloaded 2026-10-20.
name=libvdpau
version=1.5
release=1
description="Video decode and presentation API"
source=(https://gitlab.freedesktop.org/vdpau/libvdpau/-/archive/1.5/libvdpau-1.5.tar.gz)
checksums=(sha256:66490802f30426d30ff9e8af35263bbbbaa23b52d0a2d797d06959c3d19638fd)
depends=(glibc)
mode=staged

build() {
  mkdir build
  cd    build
  meson setup ..               \
        --prefix=/usr          \
        --sysconfdir=/etc      \
        --buildtype=release    \
        -D documentation=false
  ninja
  DESTDIR="$DESTDIR" ninja install
}
