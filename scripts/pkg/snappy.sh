# snappy 1.3.1: fast compression library (libsnappy.so.1). QtWebEngine links it.
# The sha256 is of GitHub's tag archive, as downloaded 2026-10-20.
name=snappy
version=1.3.1
release=1
description="Fast compression library"
source=(https://github.com/google/snappy/archive/1.3.1/snappy-1.3.1.tar.gz)
checksums=(sha256:893f708a0bf4b5529d555ffcee390e940e932fcf90261f682604475a76cd0247)
depends=(glibc)
mode=staged

build() {
  mkdir build
  cd    build
  cmake -D CMAKE_INSTALL_PREFIX=/usr     \
        -D CMAKE_INSTALL_LIBDIR=lib      \
        -D CMAKE_BUILD_TYPE=Release      \
        -D BUILD_SHARED_LIBS=ON          \
        -D SNAPPY_BUILD_TESTS=OFF        \
        -D SNAPPY_BUILD_BENCHMARKS=OFF   \
        -G Ninja ..
  ninja
  DESTDIR="$DESTDIR" ninja install
}
