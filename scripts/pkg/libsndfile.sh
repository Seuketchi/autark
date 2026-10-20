# libsndfile 1.2.2: audio file library. PulseAudio's build requires it even for the client library only.
# Built without Ogg/Vorbis/FLAC/Opus/MP3 (ENABLE_EXTERNAL_LIBS=OFF), which none of the callers here need.
# CMAKE_POLICY_VERSION_MINIMUM because its CMakeLists asks for a CMake older than 3.5, which CMake 4 refuses.
# The sha256 is of GitHub's release tarball, as downloaded 2026-10-20 (the project publishes a .asc, not a checksum).
name=libsndfile
version=1.2.2
release=1
description="Audio file reading and writing library"
source=(https://github.com/libsndfile/libsndfile/releases/download/1.2.2/libsndfile-1.2.2.tar.xz)
checksums=(sha256:3799ca9924d3125038880367bf1468e53a1b7e3686a934f098b7e1d286cdb80e)
depends=(glibc)
mode=staged

build() {
  mkdir build
  cd    build
  cmake -D CMAKE_INSTALL_PREFIX=/usr        \
        -D CMAKE_INSTALL_LIBDIR=lib        \
        -D CMAKE_BUILD_TYPE=Release        \
        -D BUILD_SHARED_LIBS=ON            \
        -D BUILD_PROGRAMS=OFF              \
        -D BUILD_EXAMPLES=OFF              \
        -D BUILD_TESTING=OFF               \
        -D ENABLE_EXTERNAL_LIBS=OFF        \
        -D ENABLE_MPEG=OFF                 \
        -D CMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -G Ninja ..
  ninja
  DESTDIR="$DESTDIR" ninja install
}
