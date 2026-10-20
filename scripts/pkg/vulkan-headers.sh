# vulkan-headers 1.4.357.0: the Vulkan API headers and registry (vulkan_core.h, vk.xml), as of Vulkan SDK 1.4.357.0, the same
# release as spirv-tools. The loader and the tools build against them; Mesa's NVK, Intel and lavapipe drivers are the Vulkan drivers.
# The sha256 is of GitHub's tag archive, as downloaded 2026-10-20.
name=vulkan-headers
version=1.4.357.0
release=1
description="Vulkan API headers"
source=(Vulkan-Headers-$version.tar.gz::https://github.com/KhronosGroup/Vulkan-Headers/archive/vulkan-sdk-$version/Vulkan-Headers-vulkan-sdk-$version.tar.gz)
checksums=(sha256:e87dce08116151f6b6d7de6b6faf41498e87e6cf848ff16fa3bd5402190ad4a3)
depends=(cmake)
mode=staged

build() {
  mkdir build
  cd    build
  cmake -D CMAKE_INSTALL_PREFIX=/usr \
        -D CMAKE_BUILD_TYPE=Release  \
        -G Ninja ..
  DESTDIR="$DESTDIR" ninja install
}
