name=ovmf
version=2025.02
release=1
description="OVMF: UEFI firmware (edk2) for qemu virtual machines, Debian's prebuilt images, for testing the installer"
source=(https://deb.debian.org/debian/pool/main/e/edk2/ovmf_2025.02-8+deb13u1_all.deb)
# The SHA256 in Debian stable's signed-by-TLS Packages index for ovmf 2025.02-8+deb13u1.
checksums=(sha256:78e0d54df11fc77406cb7a0bc9a39e5bca6d1cbe06556b91d9a73491c52decdf)
depends=()
mode=staged

# Not built from source: edk2's own build pulls about twenty git submodules that Arch's recipe leaves unpinned
# (and needs nasm and acpica), so for a test firmware this is Debian's build, pinned by hash. It installs the
# images qemu-boot.sh and scripts/qemu-test expect in /usr/share/OVMF, with Debian's copyright files.
build() {
  bsdtar -xf ovmf_2025.02-8+deb13u1_all.deb data.tar.xz
  bsdtar -xf data.tar.xz -C "$DESTDIR" ./usr/share/OVMF ./usr/share/qemu ./usr/share/doc/ovmf
}
