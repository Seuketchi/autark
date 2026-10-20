# mesa 26.1.7: from Phase 8a, the Wayland desktop (scripts/lfs/phase8a-inside.sh, pkg_mesa).
# Taken over by hand (release 2): built with glvnd=enabled, so libEGL, libGL and the GLES libraries come from libglvnd
# and Mesa installs only its driver (libEGL_mesa.so.0, libgallium, GBM, Vulkan). Programs that link libOpenGL/libGLX need that.
name=mesa
version=26.1.7
release=2
description="Mesa"
source=(https://mesa.freedesktop.org/archive/mesa-26.1.7.tar.xz)
checksums=(md5:1a3ea044abc823e2db8c6041e5adcc4f)
depends=(glslang libdrm libglvnd llvm mako pyyaml spirv-llvm-translator spirv-tools wayland-protocols)
mode=staged

build() {
  mkdir build
  cd    build
  meson setup ..                     \
        --prefix=/usr                \
        --buildtype=release          \
        --wrap-mode=nodownload       \
        -D platforms=wayland         \
        -D gallium-drivers=iris,llvmpipe \
        -D vulkan-drivers=intel,swrast   \
        -D llvm=enabled              \
        -D glvnd=enabled             \
        -D glx=disabled              \
        -D valgrind=disabled         \
        -D libunwind=disabled
  ninja
  DESTDIR="$DESTDIR" ninja install
}
