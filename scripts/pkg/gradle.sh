name=gradle
version=9.8.2
release=1
description="Gradle build tool, from the vendor's binary distribution"
source=(https://services.gradle.org/distributions/gradle-$version-bin.zip)
checksums=(sha256:21bd5da2de49b642904077f38c0efdc7778e92b3ed0889392dca61b97e389607)
depends=(temurin-jdk)
mode=staged

# The zip isn't unpacked by autark-pkg; bsdtar reads it.
build() {
  bsdtar -xf gradle-$version-bin.zip
  install -d "$DESTDIR/usr/share" "$DESTDIR/usr/bin"
  cp -a gradle-$version "$DESTDIR/usr/share/gradle"
  rm -f "$DESTDIR/usr/share/gradle/bin/gradle.bat"
  ln -s /usr/share/gradle/bin/gradle "$DESTDIR/usr/bin/gradle"
}
