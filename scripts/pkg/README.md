# Package recipes

One recipe per package, `<name>.sh`, built and installed by `autark-pkg` (autark-tools). The header is plain
assignments autark-pkg reads without running anything; `build()` is what the build runs, after `lib.sh`
(Autark's flags and `testfail`), inside the unpacked first source:

```sh
name=zlib
version=1.3.2
release=1                      # bump to rebuild the same version
description="Compression library"
source=(https://zlib.net/fossils/zlib-$version.tar.gz)    # file::url saves it under another name
checksums=(md5:a1e6c958597af3c67d162995a342138a)           # md5: or sha256:, one per source
depends=(glibc)
imports=(zlib-old)             # file lists the phase scripts recorded under other names
mode=staged                    # or tracked

build() {
  ./configure --prefix=/usr
  make
  make DESTDIR="$DESTDIR" install
}
```

- **staged**: runs as the `autark-build` user and installs into `$DESTDIR`; autark-pkg packs and signs that, then
  installs from the signed archive.
- **tracked**: for bodies that write outside `$DESTDIR` or need root (`useradd`, `chown`, tests as `tester`). It
  runs as root against the system; the files it created, and the files of packages it rewrote, are packed and
  signed afterwards. A file that was already there and no package owns is reported, not claimed.

The build sees `$srcdir` (the folder holding the sources), `$DESTDIR` (staged only), `$LOGS` and `$ROOT`.

## Converted recipes

Every recipe carrying the `GENERATED` line comes from the phase scripts (`scripts/lfs/*-inside.sh`):

    python3 -I scripts/pkg/convert.py

It keeps each function body, makes a body staged when every install command can take `DESTDIR` and nothing
else writes outside it, and takes sources and checksums from `sources/lfs-13.1-*` (the book's lists),
`docs/specs/phase-8a-packages.md` and `sources/extra.tsv`. Dependencies come from the spec's "Needed by"
column and the table at the top of `convert.py`; chapter 8's base system has none beyond its order (`order`).
Delete the `GENERATED` line to take a recipe over by hand: the converter never touches it again.

Not converted: chapter 8's stripping and cleanup, and the machine's own steps (initramfs, Secure Boot key,
UKI, services), which stay in their phase scripts; the kernel stays with `ch10-kernel-inside.sh`.

## Recipes imported from Arch Linux

`scripts/arch-import.py <package>...` turns Arch's recipe (its PKGBUILD, from gitlab.archlinux.org, pinned to the commit it read)
into one of ours. `autark-pkg install <package>` runs it for a package with no recipe (as the `autark-build` user), into
`/var/lib/autark/imported`, below the hand-written recipes here.

- Every source is downloaded and checked against the PKGBUILD's hash; the recipe records its sha256. A `git+https://github.com/o/r#tag=X`
  source becomes the host's tag archive, which has no hash to check, so it is pinned by the sha256 first seen (the recipe says so).
- `depends` and `makedepends` are mapped through `pkg/arch-names.map` (`archname autarkname`; `-` means nothing to depend on). Runtime
  dependencies with no recipe are imported too (`-r`, which `autark-pkg` passes); missing build-time ones are only reported, unless `--make-deps`.
- `build()` unpacks the sources as makepkg does and runs the PKGBUILD's own `prepare()`, `build()` and `package()` with `$srcdir` and
  `$pkgdir` set (and `DESTDIR` unset, as under makepkg). `check()` is not run.
- `arch-overrides/<name>.map` records a deliberate difference: `drop <dependency>` and `sub <old> => <new>` in the PKGBUILD's functions
  (it must match, so an Arch update that moves it is noticed). `lm_sensors` drops `rrdtool` and the `sensord` logger it needs.
- Importing again keeps a recipe's release when nothing changed, and raises it when the contents did, so a kept build of the old
  contents is not reused.
- Not handled, and reported: git sources from hosts other than GitHub and GitLab, without a tag or commit, or with submodules; install
  scripts (`*.install`); a split package's own `depends`; packages whose PKGBUILD fetches during the build (most Rust and Go ones).

