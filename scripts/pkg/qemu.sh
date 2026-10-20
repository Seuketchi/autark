name=qemu
version=11.1.2
release=1
description="QEMU system emulator for x86_64 (KVM), with qemu-img and qemu-nbd; no GUI, no docs, no user-mode emulation"
source=(https://download.qemu.org/qemu-$version.tar.xz)
# qemu.org publishes only GPG signatures for its tarballs, so this is the sha256 of the file as first downloaded.
checksums=(sha256:731b5681e4bb18be313231579b8efd0296c5b015fa36dc533874b639ba838016)
depends=(glibc glib pixman zlib zstd)
mode=staged

# x86_64 only, for the installer test (docs/specs/installer.md): UEFI firmware (OVMF), an emulated NVMe disk, a serial
# console and VNC. No GTK/SDL/OpenGL, so no graphics stack is needed; Rust, docs and the guest agent are left out.
build() {
  mkdir build && cd build
  ../configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
               --target-list=x86_64-softmmu --enable-kvm \
               --disable-docs --disable-gtk --disable-sdl --disable-opengl --disable-guest-agent \
               --disable-user --disable-rust --disable-werror --disable-download
  ninja
  DESTDIR="$DESTDIR" ninja install
}
