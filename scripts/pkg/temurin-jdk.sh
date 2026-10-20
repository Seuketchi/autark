name=temurin-jdk
version=21.0.12.1
release=1
description="Eclipse Temurin JDK 21 (LTS), Adoptium's build of OpenJDK, from the vendor's binary"
source=(OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz::https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz)
checksums=(sha256:ce79869e1307ed8ee1e2baa86a412b1eb5b75d10a01006d788a6f968bcfaee94)
depends=(glibc zlib)
mode=staged

# Arch builds OpenJDK from source, which needs a JDK to bootstrap, so this one is the vendor's binary, pinned by hash.
build() {
  jvm=/usr/lib/jvm/temurin-21
  install -d "$DESTDIR$jvm" "$DESTDIR/usr/bin" "$DESTDIR/etc/profile.d"
  cp -a . "$DESTDIR$jvm"
  for tool in "$DESTDIR$jvm"/bin/*; do
    ln -s "$jvm/bin/${tool##*/}" "$DESTDIR/usr/bin/${tool##*/}"
  done
  echo "export JAVA_HOME=$jvm" > "$DESTDIR/etc/profile.d/java.sh"
}
