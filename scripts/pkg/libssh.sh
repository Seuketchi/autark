# libssh 0.11.5: SSH client/server library (libssh.so.4). Viber's bundled ffmpeg (libavformat) links it.
# GSSAPI, the server and the examples are off. The sha256 is of libssh.org's tarball, as downloaded 2026-10-20
# (the project publishes a .asc, not a checksum).
name=libssh
version=0.11.5
release=1
description="SSH library"
source=(https://www.libssh.org/files/0.11/libssh-0.11.5.tar.xz)
checksums=(sha256:6898ba9dd836d618b71dc7a4bb786a502c173cef5cafbf20fe5e0567ba4ea30c)
depends=(glibc openssl zlib)
mode=staged

build() {
  mkdir build
  cd    build
  cmake -D CMAKE_INSTALL_PREFIX=/usr     \
        -D CMAKE_INSTALL_LIBDIR=lib      \
        -D CMAKE_BUILD_TYPE=Release      \
        -D WITH_GSSAPI=OFF               \
        -D WITH_SERVER=OFF               \
        -D WITH_EXAMPLES=OFF             \
        -D UNIT_TESTING=OFF              \
        -G Ninja ..
  ninja
  DESTDIR="$DESTDIR" ninja install
}
