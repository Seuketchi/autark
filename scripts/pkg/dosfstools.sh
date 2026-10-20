# dosfstools 4.2: mkfs.fat, fsck.fat and fatlabel, for making and checking FAT file systems (USB sticks, the EFI partition).
# The kernel reads and writes FAT already; this is the missing formatter. Without udev (it only adds a rule for fsck of FAT labels).
# The sha256 is of the GitHub release tarball, as downloaded 2026-10-20 (the project publishes no checksum).
name=dosfstools
version=4.2
release=1
description="Tools to make and check FAT file systems"
source=(https://github.com/dosfstools/dosfstools/releases/download/v4.2/dosfstools-4.2.tar.gz)
checksums=(sha256:64926eebf90092dca21b14259a5301b7b98e7b1943e8a201c7d726084809b527)
depends=(glibc)
mode=staged

build() {
  ./configure --prefix=/usr             \
              --sbindir=/usr/sbin       \
              --enable-compat-symlinks  \
              --without-udev            \
              --docdir=/usr/share/doc/dosfstools-4.2
  make
  make DESTDIR="$DESTDIR" install
}
