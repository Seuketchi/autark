# pulseaudio 17.0, client library only (libpulse.so.0, libpulse-simple.so.0). Viber's bundled QtMultimedia links libpulse.
# No daemon: PipeWire is the sound server here, and its pipewire-pulse speaks the PulseAudio protocol to this library.
# The sha256 is of freedesktop.org's release tarball, as downloaded 2026-10-20 (the project publishes no checksum).
name=libpulse
version=17.0
release=1
description="PulseAudio client library"
source=(https://www.freedesktop.org/software/pulseaudio/releases/pulseaudio-17.0.tar.xz)
checksums=(sha256:053794d6671a3e397d849e478a80b82a63cb9d8ca296bd35b73317bb5ceb87b5)
depends=(glibc libsndfile)
mode=staged

build() {
  mkdir build
  cd    build
  meson setup ..                 \
        --prefix=/usr            \
        --sysconfdir=/etc        \
        --localstatedir=/var     \
        --buildtype=release      \
        -D daemon=false          \
        -D doxygen=false         \
        -D man=false             \
        -D tests=false           \
        -D alsa=disabled         \
        -D bluez5=disabled       \
        -D dbus=disabled         \
        -D glib=disabled         \
        -D gsettings=disabled    \
        -D gstreamer=disabled    \
        -D gtk=disabled          \
        -D jack=disabled         \
        -D lirc=disabled         \
        -D openssl=disabled      \
        -D orc=disabled          \
        -D systemd=disabled      \
        -D udev=disabled         \
        -D valgrind=disabled     \
        -D x11=disabled
  ninja
  DESTDIR="$DESTDIR" ninja install
}
