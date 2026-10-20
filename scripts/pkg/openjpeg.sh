# openjpeg 2.5.4: JPEG 2000 codec library (libopenjp2.so.7). Viber's bundled ffmpeg (libavcodec) links it.
# Library only: the command-line codec, docs and tests are off. The sha256 is of GitHub's tag archive, as downloaded 2026-10-20.
name=openjpeg
version=2.5.4
release=1
description="JPEG 2000 codec library"
source=(https://github.com/uclouvain/openjpeg/archive/v2.5.4/openjpeg-2.5.4.tar.gz)
checksums=(sha256:a695fbe19c0165f295a8531b1e4e855cd94d0875d2f88ec4b61080677e27188a)
depends=(glibc)
mode=staged

build() {
  mkdir build
  cd    build
  cmake -D CMAKE_INSTALL_PREFIX=/usr     \
        -D CMAKE_INSTALL_LIBDIR=lib      \
        -D CMAKE_BUILD_TYPE=Release      \
        -D BUILD_STATIC_LIBS=OFF         \
        -D BUILD_CODEC=OFF               \
        -D BUILD_DOC=OFF                 \
        -D BUILD_TESTING=OFF             \
        -G Ninja ..
  ninja
  DESTDIR="$DESTDIR" ninja install
}
