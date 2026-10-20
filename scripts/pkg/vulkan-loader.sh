# vulkan-loader 1.4.357.0: libvulkan.so.1, which programs link and which finds the drivers listed in /usr/share/vulkan/icd.d
# (Mesa installs intel, lavapipe and, from mesa 26.1.7-3, nouveau/NVK). Wayland support only: Autark has no X11 libraries.
# The sha256 is of GitHub's tag archive, as downloaded 2026-10-20.
name=vulkan-loader
version=1.4.357.0
release=1
description="Vulkan loader (libvulkan)"
source=(Vulkan-Loader-$version.tar.gz::https://github.com/KhronosGroup/Vulkan-Loader/archive/vulkan-sdk-$version/Vulkan-Loader-vulkan-sdk-$version.tar.gz)
checksums=(sha256:54f2537df22313768da0317dda2abdaaab7711b4081c48c869a79db343d0ae70)
depends=(cmake pkgconf python vulkan-headers wayland)
mode=staged

build() {
  mkdir build
  cd    build
  cmake -D CMAKE_INSTALL_PREFIX=/usr             \
        -D CMAKE_INSTALL_SYSCONFDIR=/etc         \
        -D CMAKE_INSTALL_DATADIR=/share          \
        -D CMAKE_INSTALL_LIBDIR=lib              \
        -D CMAKE_BUILD_TYPE=Release              \
        -D CMAKE_SKIP_RPATH=ON                   \
        -D BUILD_TESTS=OFF                       \
        -D BUILD_WSI_XCB_SUPPORT=OFF             \
        -D BUILD_WSI_XLIB_SUPPORT=OFF            \
        -D BUILD_WSI_XLIB_XRANDR_SUPPORT=OFF     \
        -D BUILD_WSI_WAYLAND_SUPPORT=ON          \
        -G Ninja ..
  ninja
  DESTDIR="$DESTDIR" ninja install
}
