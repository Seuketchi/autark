# vulkan-tools 1.4.357.0: vulkaninfo, to see which GPUs the Vulkan loader finds (`vulkaninfo --summary`). No vkcube (it needs
# glslang and a window system build), and not the mock driver (BUILD_ICD=OFF), which would list a fake GPU.
# The sha256 is of GitHub's tag archive, as downloaded 2026-10-20.
name=vulkan-tools
version=1.4.357.0
release=1
description="vulkaninfo"
source=(Vulkan-Tools-$version.tar.gz::https://github.com/KhronosGroup/Vulkan-Tools/archive/vulkan-sdk-$version/Vulkan-Tools-vulkan-sdk-$version.tar.gz)
checksums=(sha256:6c94b86c850808aba316d999dd6742133d6197ae2135248d3a8aed9b32ebd1f7)
depends=(cmake pkgconf python vulkan-headers vulkan-loader wayland)
mode=staged

build() {
  mkdir build
  cd    build
  cmake -D CMAKE_INSTALL_PREFIX=/usr         \
        -D CMAKE_BUILD_TYPE=Release          \
        -D BUILD_CUBE=OFF                    \
        -D BUILD_ICD=OFF                     \
        -D BUILD_TESTS=OFF                   \
        -D BUILD_WSI_XCB_SUPPORT=OFF         \
        -D BUILD_WSI_XLIB_SUPPORT=OFF        \
        -D BUILD_WSI_WAYLAND_SUPPORT=ON      \
        -G Ninja ..
  ninja
  DESTDIR="$DESTDIR" ninja install
}
