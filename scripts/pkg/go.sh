# go 1.27.3: hand-written. Go is built by an earlier Go, and Arch's recipe uses the go package for that, which cannot exist before
# the first one. The official go1.24.6 binary release (checksum from go.dev/dl) is the bootstrap, as a second source: it is only
# unpacked in the build folder, so nothing of it is installed.
name=go
version=1.27.3
release=3
description="Core compiler tools for the Go programming language"
source=(
  go1.27.3.src.tar.gz::https://go.dev/dl/go1.27.3.src.tar.gz
  go1.24.6.linux-amd64.tar.gz::https://go.dev/dl/go1.24.6.linux-amd64.tar.gz
)
checksums=(
  sha256:6e7749035cf360f06b2575d162ea79df9fda8ef671889e5c375f8e50777f26bb
  sha256:bbca37cc395c974ffa4893ee35819ad23ebb27426df87af92e93a9ec66ef8712
)
depends=()
mode=staged

build() {
cd "$srcdir"
mkdir bootstrap
tar -xf go1.24.6.linux-amd64.tar.gz -C bootstrap --strip-components=1
export GOROOT_BOOTSTRAP="$srcdir/bootstrap" GOROOT_FINAL=/usr/lib/go GOEXPERIMENT=nodwarf5
( cd go/src && ./make.bash -v )
cd go
install -d "$DESTDIR/usr/bin" "$DESTDIR/usr/lib/go" "$DESTDIR/usr/share/doc/go"
cp -a bin pkg src lib misc api test "$DESTDIR/usr/lib/go"
cp -r doc/* "$DESTDIR/usr/share/doc/go"
ln -sf /usr/lib/go/bin/go "$DESTDIR/usr/bin/go"
ln -sf /usr/lib/go/bin/gofmt "$DESTDIR/usr/bin/gofmt"
ln -sf /usr/share/doc/go "$DESTDIR/usr/lib/go/doc"
install -Dm644 VERSION "$DESTDIR/usr/lib/go/VERSION"
rm -rf "$DESTDIR/usr/lib/go/pkg/bootstrap" "$DESTDIR"/usr/lib/go/pkg/obj/go-build
install -Dm644 go.env "$DESTDIR/usr/lib/go/go.env"
install -Dm644 LICENSE "$DESTDIR/usr/share/licenses/go/LICENSE"
}
