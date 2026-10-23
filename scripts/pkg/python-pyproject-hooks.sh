# python-pyproject-hooks 1.3.3: hand-written. Arch's recipe builds it with python-build, which needs it back (python-build,
# python-installer and python-pyproject-hooks depend on each other); pip and the flit-core already here build it without that.
name=python-pyproject-hooks
version=1.3.3
release=1
description="Wrappers to call pyproject.toml-based build backend hooks"
source=(pypi-pyproject_hooks-1.3.3.tar.gz::https://files.pythonhosted.org/packages/source/p/pyproject_hooks/pyproject_hooks-1.3.3.tar.gz)
checksums=(sha256:defda19b854fa0d3bd4f76ea4ddcba8abd7dcfcdd585a6690ade050744fc5f43)
depends=(python flit-core)
mode=staged

build() {
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --root="$DESTDIR" --ignore-installed --no-index --no-deps --find-links dist pyproject_hooks
}
