#!/bin/bash
# Build guide Step 3: LFS 13.1-systemd chapter 5, the cross-toolchain. Commands are the book's, verbatim.
# Run as lfs:   cp this file to $LFS/sources, then scripts/as-lfs.sh 'bash $LFS/sources/ch5-cross-toolchain.sh [package...]'
# Each package: unpack in $LFS/sources, build, delete the build folder. Logs go to $LFS/sources/logs/.
set -euo pipefail

: "${LFS:?run through as-lfs.sh}" "${LFS_TGT:?run through as-lfs.sh}"
logs=$LFS/sources/logs
mkdir -p "$logs"
srcdir=$LFS/sources
source "$(dirname "$0")/build-lib.sh"


pkg_binutils_pass1() {
  mkdir -v build
  cd       build
  ../configure --prefix=$LFS/tools \
               --with-sysroot=$LFS \
               --target=$LFS_TGT   \
               --disable-nls       \
               --enable-gprofng=no \
               --disable-werror    \
               --enable-new-dtags  \
               --enable-default-hash-style=gnu
  make
  make install
}

pkg_gcc_pass1() {
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
  ../configure                  \
      --target=$LFS_TGT         \
      --prefix=$LFS/tools       \
      --with-glibc-version=2.44 \
      --with-sysroot=$LFS       \
      --with-newlib             \
      --without-headers         \
      --enable-default-pie      \
      --enable-default-ssp      \
      --disable-fixincludes     \
      --disable-nls             \
      --disable-shared          \
      --disable-multilib        \
      --disable-threads         \
      --disable-libatomic       \
      --disable-libgomp         \
      --disable-libquadmath     \
      --disable-libssp          \
      --disable-libvtv          \
      --disable-libstdcxx       \
      --enable-languages=c,c++
  make
  make install
  cat ../gcc/{limitx,glimits,limity}.h  > \
    $($LFS_TGT-gcc -print-file-name=include)/limits.h
}

pkg_linux_headers() {
  make mrproper
  make headers
  find usr/include -type f ! -name '*.h' -delete
  cp -rv usr/include $LFS/usr
}

pkg_glibc() {
  case $(uname -m) in
      i?86)   ln -sfv ld-linux.so.2 $LFS/lib/ld-lsb.so.3
      ;;
      x86_64) ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64
              ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3
      ;;
  esac
  patch -Np1 -i ../glibc-fhs-1.patch
  patch -Np1 -i ../glibc-2.44-upstream_fixes-1.patch
  mkdir -v build
  cd       build
  echo "rootsbindir=/usr/sbin" > configparms
  ../configure                             \
        --prefix=/usr                      \
        --host=$LFS_TGT                    \
        --build=$(../scripts/config.guess) \
        --disable-nscd                     \
        libc_cv_slibdir=/usr/lib           \
        --enable-kernel=5.10
  make
  make DESTDIR=$LFS install
  sed '/RTLDLIST=/s@/usr@@g' -i $LFS/usr/bin/ldd
}

pkg_gcc_libstdcxx() {
  mkdir -v build
  cd       build
  ../libstdc++-v3/configure      \
      --host=$LFS_TGT            \
      --build=$(../config.guess) \
      CXX=$LFS_TGT-gcc           \
      --prefix=/usr              \
      --disable-multilib         \
      --disable-nls              \
      --disable-libstdcxx-pch    \
      --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/16.2.0
  make
  make DESTDIR=$LFS install
  rm -v $LFS/usr/lib/lib{stdc++{,exp,fs},supc++}.la
}

# The book's sanity check after glibc: a test program must use $LFS's loader and start files.
pkg_sanity_check() {
  cd "$(mktemp -d)"
  echo 'int main(){}' | $LFS_TGT-gcc -x c - -v -Wl,--verbose &> dummy.log
  $LFS_TGT-readelf -l a.out | grep ': /lib'
  grep -E -o "$LFS/lib.*/S?crt[1in].*succeeded" dummy.log
  grep -B3 "^ $LFS/usr/include" dummy.log
  grep 'SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g'
  grep "/lib.*/libc.so.6 " dummy.log
  grep found dummy.log
  # Stop the build if the interpreter isn't $LFS's /lib64 loader.
  $LFS_TGT-readelf -l a.out | grep -q '\[Requesting program interpreter: /lib64/ld-linux-x86-64.so.2\]'
  rm -v a.out dummy.log
}

packages=("${@:-binutils_pass1 gcc_pass1 linux_headers glibc sanity_check gcc_libstdcxx}")
for p in ${packages[@]}; do
  case $p in
    binutils_pass1) build binutils-2.47.tar.xz pkg_binutils_pass1 ;;
    gcc_pass1)      build gcc-16.2.0.tar.xz    pkg_gcc_pass1 ;;
    linux_headers)  build linux-7.1.8.tar.xz   pkg_linux_headers ;;
    glibc)          build glibc-2.44.tar.xz    pkg_glibc ;;
    sanity_check)   echo "== sanity check"; (set -e; pkg_sanity_check) ;;
    gcc_libstdcxx)  build gcc-16.2.0.tar.xz    pkg_gcc_libstdcxx ;;
    *) echo "unknown package: $p" >&2; exit 2 ;;
  esac
done
echo "== chapter 5 done"
