# tmux 3.8: terminal multiplexer. Built without utf8proc, systemd integration and sixel; its config is ~/.tmux.conf.
# The sha256 is of GitHub's release tarball (no publisher checksum was found), as downloaded 2026-10-20.
name=tmux
version=3.8
release=1
description="Terminal multiplexer"
source=(https://github.com/tmux/tmux/releases/download/3.8/tmux-3.8.tar.gz)
checksums=(sha256:e79c699c7e949dccd0a4a125e17b8d1261e311b16979dbc8eb34542f3966d82e)
depends=(glibc libevent ncurses)
mode=staged

build() {
  ./configure --prefix=/usr
  make
  make DESTDIR="$DESTDIR" install
}
