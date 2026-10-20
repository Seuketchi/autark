# mesa 26.1.7: from Phase 8a, the Wayland desktop (scripts/lfs/phase8a-inside.sh, pkg_mesa).
# Taken over by hand (release 3). Built with glvnd=enabled, so libEGL, libGL and the GLES libraries come from libglvnd
# and Mesa installs only its driver (libEGL_mesa.so.0, libgallium, GBM, Vulkan). Programs that link libOpenGL/libGLX need that.
# Also NVK, the open NVIDIA Vulkan driver, and nouveau's OpenGL driver, for the RTX 3050 (docs/specs/nvk.md).
# NVK is written partly in Rust: bindgen and cbindgen are its build tools, and six crates its Meson wraps name are sources here
# (the hashes are the wraps' own), put where Meson looks first so the build needs no network.
name=mesa
version=26.1.7
release=3
description="Mesa"
source=(
  https://mesa.freedesktop.org/archive/mesa-26.1.7.tar.xz
  paste-1.0.14.tar.gz::https://crates.io/api/v1/crates/paste/1.0.14/download
  rustc-hash-2.1.1.tar.gz::https://crates.io/api/v1/crates/rustc-hash/2.1.1/download
  syn-2.0.87.tar.gz::https://crates.io/api/v1/crates/syn/2.0.87/download
  proc-macro2-1.0.86.tar.gz::https://crates.io/api/v1/crates/proc-macro2/1.0.86/download
  quote-1.0.35.tar.gz::https://crates.io/api/v1/crates/quote/1.0.35/download
  unicode-ident-1.0.12.tar.gz::https://crates.io/api/v1/crates/unicode-ident/1.0.12/download
)
checksums=(
  md5:1a3ea044abc823e2db8c6041e5adcc4f
  sha256:de3145af08024dea9fa9914f381a17b8fc6034dfb00f3a84013f7ff43f29ed4c
  sha256:357703d41365b4b27c590e3ed91eabb1b663f07c4c084095e60cbed4362dff0d
  sha256:25aa4ce346d03a6dcd68dd8b4010bcb74e54e62c90c573f394c46eae99aba32d
  sha256:5e719e8df665df0d1c8fbfd238015744736151d4445ec0836b8e628aae103b77
  sha256:291ec9ab5efd934aaf503a6466c5d5251535d108ee747472c3977cc5acc868ef
  sha256:3354b9ac3fae1ff6755cb6db53683adb661634f67557942dea4facebec0fee4b
)
depends=(bindgen cbindgen glslang libdrm libglvnd llvm mako pyyaml spirv-llvm-translator spirv-tools wayland-protocols)
mode=staged

build() {
  mkdir -p subprojects/packagecache
  for crate in paste-1.0.14 rustc-hash-2.1.1 syn-2.0.87 proc-macro2-1.0.86 quote-1.0.35 unicode-ident-1.0.12; do
    cp "$srcdir/$crate.tar.gz" subprojects/packagecache/
  done
  mkdir build
  cd    build
  meson setup ..                     \
        --prefix=/usr                \
        --buildtype=release          \
        --wrap-mode=nodownload       \
        -D platforms=wayland         \
        -D gallium-drivers=iris,llvmpipe,nouveau \
        -D vulkan-drivers=intel,swrast,nouveau \
        -D llvm=enabled              \
        -D glvnd=enabled             \
        -D glx=disabled              \
        -D valgrind=disabled         \
        -D libunwind=disabled
  ninja
  DESTDIR="$DESTDIR" ninja install
}
