# libevent 2.1.13: tmux needs it. OpenSSL support is off (tmux doesn't use it), and so are the samples and regression tests.
name=libevent
version=2.1.13
release=1
description="Event notification library"
source=(https://github.com/libevent/libevent/releases/download/release-2.1.13-stable/libevent-2.1.13-stable.tar.gz)
checksums=(sha256:f7e9383b8c0baa81b687e5b5eecc01beefaf1b19b64151d95ed61647fe7a315c)
depends=(glibc)
mode=staged

build() {
  ./configure --prefix=/usr             \
              --disable-static          \
              --disable-openssl         \
              --disable-samples         \
              --disable-libevent-regress
  make
  make DESTDIR="$DESTDIR" install
}
