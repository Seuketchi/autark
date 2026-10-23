# python-build 1.6.1: hand-written. Arch's recipe builds it with python-build, which needs it back (python-build,
# python-installer and python-pyproject-hooks depend on each other); pip and the flit-core already here build it without that.
name=python-build
version=1.6.1
release=1
description="A simple, correct Python build frontend"
source=(pypi-build-1.6.1.tar.gz::https://files.pythonhosted.org/packages/source/b/build/build-1.6.1.tar.gz)
checksums=(sha256:51cc11666391ab6f092070437ac747002ff46f3e4113a3622177ee6b488bfc53)
depends=(python packaging python-pyproject-hooks flit-core)
mode=staged

build() {
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --root="$DESTDIR" --ignore-installed --no-index --no-deps --find-links dist build
}
