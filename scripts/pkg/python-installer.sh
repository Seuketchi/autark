# python-installer 1.1.0: hand-written. Arch's recipe builds it with python-build, which needs it back (python-build,
# python-installer and python-pyproject-hooks depend on each other); pip and the flit-core already here build it without that.
name=python-installer
version=1.1.0
release=1
description="Low-level library for installing a Python package from a wheel distribution"
source=(pypi-installer-1.1.0.tar.gz::https://files.pythonhosted.org/packages/source/i/installer/installer-1.1.0.tar.gz)
checksums=(sha256:5adc0c01ce62d809989e246987cd68944fe5df8af562d0358f65b2ab15cb5de7)
depends=(python flit-core)
mode=staged

build() {
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --root="$DESTDIR" --ignore-installed --no-index --no-deps --find-links dist installer
}
