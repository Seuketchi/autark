#!/bin/bash
# Build guide Step 4, part 1: LFS 13.1-systemd chapter 6, temporary tools (cross-compiled, as lfs).
# Generated from the book's pages; each function body is the book's commands, verbatim.
# Run as lfs:   cp this file to $LFS/sources, then scripts/as-lfs.sh 'bash $LFS/sources/ch6-temporary-tools.sh [package...]'
set -euo pipefail

: "${LFS:?run through as-lfs.sh}" "${LFS_TGT:?run through as-lfs.sh}"
logs=$LFS/sources/logs
mkdir -p "$logs"
srcdir=$LFS/sources
source "$(dirname "$0")/build-lib.sh"


pkg_m4() {
  cat > $LFS/usr/share/config.site << EOF
ac_cv_func_posix_spawn_file_actions_addchdir=yes
ac_cv_func_posix_spawn_file_actions_addfchdir=yes
EOF
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              --build=$(build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

pkg_ncurses() {
  mkdir build
  pushd build
    ../configure --prefix=$LFS/tools AWK=gawk
    make -C include
    make -C progs tic
    install progs/tic $LFS/tools/bin
  popd
  ./configure --prefix=/usr                \
              --host=$LFS_TGT              \
              --build=$(./config.guess)    \
              --mandir=/usr/share/man      \
              --with-manpage-format=normal \
              --with-shared                \
              --without-normal             \
              --with-cxx-shared            \
              --without-debug              \
              --without-ada                \
              --disable-stripping          \
              AWK=gawk
  make
  make DESTDIR=$LFS install
  ln -sv libncursesw.so $LFS/usr/lib/libncurses.so
  sed -e 's/^#if.*XOPEN.*$/#if 1/' \
      -i $LFS/usr/include/curses.h
}

pkg_bash() {
  ./configure --prefix=/usr                      \
              --build=$(sh support/config.guess) \
              --host=$LFS_TGT                    \
              --without-bash-malloc              \
              --docdir=/usr/share/doc/bash-5.3
  make
  make DESTDIR=$LFS install
  ln -sv bash $LFS/bin/sh
}

pkg_coreutils() {
  ./configure --prefix=/usr                     \
              --host=$LFS_TGT                   \
              --build=$(build-aux/config.guess) \
              --enable-install-program=hostname
  make
  make DESTDIR=$LFS install
  mv -v $LFS/usr/bin/chroot              $LFS/usr/sbin
  mkdir -pv $LFS/usr/share/man/man8
  mv -v $LFS/usr/share/man/man1/chroot.1 $LFS/usr/share/man/man8/chroot.8
  sed -i 's/"1"/"8"/'                    $LFS/usr/share/man/man8/chroot.8
}

pkg_diffutils() {
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              gl_cv_func_strcasecmp_works=yes \
              --build=$(./build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

pkg_file() {
  mkdir build
  pushd build
    ../configure --disable-bzlib      \
                 --disable-libseccomp \
                 --disable-xzlib      \
                 --disable-zlib
    make
  popd
  ./configure --prefix=/usr --host=$LFS_TGT --build=$(./config.guess)
  make FILE_COMPILE=$(pwd)/build/src/file
  make DESTDIR=$LFS install
  rm -v $LFS/usr/lib/libmagic.la
}

pkg_findutils() {
  ./configure --prefix=/usr                   \
              --localstatedir=/var/lib/locate \
              --host=$LFS_TGT                 \
              --build=$(build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

pkg_gawk() {
  sed -i 's/extras//' Makefile.in
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              --build=$(build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

pkg_grep() {
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              --build=$(./build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

pkg_gzip() {
  ./configure --prefix=/usr --host=$LFS_TGT
  make
  make DESTDIR=$LFS install
}

pkg_make() {
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              --build=$(build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

pkg_patch() {
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              --build=$(build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

pkg_sed() {
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              --build=$(./build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

pkg_tar() {
  ./configure --prefix=/usr   \
              --host=$LFS_TGT \
              --build=$(build-aux/config.guess)
  make
  make DESTDIR=$LFS install
}

pkg_xz() {
  ./configure --prefix=/usr                     \
              --host=$LFS_TGT                   \
              --build=$(build-aux/config.guess) \
              --disable-static                  \
              --docdir=/usr/share/doc/xz-5.8.3
  make
  make DESTDIR=$LFS install
  rm -v $LFS/usr/lib/liblzma.la
}

pkg_binutils_pass2() {
  sed '6031s/$add_dir//' -i ltmain.sh
  mkdir -v build
  cd       build
  ../configure                   \
      --prefix=/usr              \
      --build=$(../config.guess) \
      --host=$LFS_TGT            \
      --disable-nls              \
      --enable-shared            \
      --enable-gprofng=no        \
      --disable-werror           \
      --enable-64-bit-bfd        \
      --enable-new-dtags         \
      --enable-default-hash-style=gnu
  make
  make DESTDIR=$LFS install
  rm -v $LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
}

pkg_gcc_pass2() {
  tar -xf ../mpfr-4.2.2.tar.xz
  mv -v mpfr-4.2.2 mpfr
  tar -xf ../gmp-6.3.0.tar.xz
  mv -v gmp-6.3.0 gmp
  tar -xf ../mpc-1.4.1.tar.xz
  mv -v mpc-1.4.1 mpc
  case $(uname -m) in
    x86_64)
      sed -e '/m64=/s/lib64/lib/' \
          -i.orig gcc/config/i386/t-linux64
    ;;
  esac
  mkdir -v build
  cd       build
  ../configure                   \
      --build=$(../config.guess) \
      --host=$LFS_TGT            \
      --target=$LFS_TGT          \
      --prefix=/usr              \
      --with-build-sysroot=$LFS  \
      --enable-default-pie       \
      --enable-default-ssp       \
      --disable-fixincludes      \
      --disable-nls              \
      --disable-multilib         \
      --disable-libatomic        \
      --disable-libgomp          \
      --disable-libquadmath      \
      --disable-libsanitizer     \
      --disable-libssp           \
      --disable-libvtv           \
      --enable-languages=c,c++   \
      CXX_FOR_TARGET="$LFS_TGT-gcc -nostdinc++" \
      LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc \
      target_configargs=gcc_cv_target_thread_file=posix
  make
  make DESTDIR=$LFS install
  ln -sv gcc $LFS/usr/bin/cc
}

packages=("${@:-m4 ncurses bash coreutils diffutils file findutils gawk grep gzip make patch sed tar xz binutils_pass2 gcc_pass2}")
for p in ${packages[@]}; do
  case $p in
    m4) build m4-1.4.21.tar.xz pkg_m4 ;;
    ncurses) build ncurses-6.6.tar.gz pkg_ncurses ;;
    bash) build bash-5.3.tar.gz pkg_bash ;;
    coreutils) build coreutils-9.11.tar.xz pkg_coreutils ;;
    diffutils) build diffutils-3.12.tar.xz pkg_diffutils ;;
    file) build file-5.48.tar.gz pkg_file ;;
    findutils) build findutils-4.11.0.tar.xz pkg_findutils ;;
    gawk) build gawk-5.4.1.tar.xz pkg_gawk ;;
    grep) build grep-3.12.tar.xz pkg_grep ;;
    gzip) build gzip-1.14.tar.xz pkg_gzip ;;
    make) build make-4.4.1.tar.gz pkg_make ;;
    patch) build patch-2.8.tar.xz pkg_patch ;;
    sed) build sed-4.10.tar.xz pkg_sed ;;
    tar) build tar-1.35.tar.xz pkg_tar ;;
    xz) build xz-5.8.3.tar.xz pkg_xz ;;
    binutils_pass2) build binutils-2.47.tar.xz pkg_binutils_pass2 ;;
    gcc_pass2) build gcc-16.2.0.tar.xz pkg_gcc_pass2 ;;
    *) echo "unknown package: $p" >&2; exit 2 ;;
  esac
done
echo "== chapter 6 done"
