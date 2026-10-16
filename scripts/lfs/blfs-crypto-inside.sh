#!/bin/bash
# Before build guide Step 6: disk encryption and TPM support, so Autark can unlock its own LUKS root and
# enroll TPM+PIN. Runs INSIDE the chroot as root, started by ch7-chroot.sh with INSIDE=blfs-crypto-inside.sh.
#
# libaio → LVM2 (device-mapper) ─┐
# popt ──────────────────────────┼→ cryptsetup ─┐
# CMake → json-c ────────────────┘              ├→ systemd rebuilt with libcryptsetup, tpm2, ukify
# json-c, OpenSSL → tpm2-tss ───────────────────┤
# pefile (Python, ukify needs it) ──────────────┘
#
# Commands follow BLFS 13.1-systemd except where marked [Autark]. tpm2-tss and pefile aren't in BLFS.
# Sources and how each was verified: see log.md, 2026-10-17 "Disk encryption and TPM".
set -euo pipefail

if [ ! -e /sources/wget-list-systemd ] || grep -qi ubuntu /etc/os-release 2>/dev/null; then
  echo "blfs-crypto-inside.sh: not inside the Autark chroot; refusing to run" >&2
  exit 1
fi

logs=/sources/logs
mkdir -p "$logs" /sources/.done /sources/.track /var/lib/autark/files
srcdir=/sources
source "$(dirname "$0")/build-lib.sh"

export CFLAGS="-O2 -march=x86-64-v3 -pipe -fstack-protector-strong -fstack-clash-protection -fcf-protection=full -D_FORTIFY_SOURCE=3"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-Wl,-O1 -Wl,-z,relro -Wl,-z,now"

testfail() { echo "== TESTFAIL: $*"; echo "$(date +%T) $*" >> "$logs/test-failures.txt"; }

snapshot() {
  find / -xdev \( -path /sources -o -path /tmp -o -path /root -o -path /var/lib/autark \) -prune \
    -o \( -type f -o -type l \) -print | LC_ALL=C sort
}

run_pkg() {
  local name=$1 tarball=$2 fn=$3
  if [ -e "/sources/.done/blfs-$name" ]; then echo "== $name: already done, skipped"; return; fi
  snapshot > /sources/.track/before
  if [ "$tarball" = - ]; then
    echo "== $fn: started $(date +%T)"
    set +e; ( set -e; cd /sources; "$fn" ) > "$logs/$fn.log" 2>&1; local rc=$?; set -e
    if [ "$rc" != 0 ]; then echo "== $fn: FAILED (exit $rc)"; tail -25 "$logs/$fn.log"; exit 1; fi
    echo "== $fn: done"
  else
    build "$tarball" "$fn"
  fi
  snapshot | LC_ALL=C comm -13 /sources/.track/before - > "/var/lib/autark/files/$name"
  echo "   $(wc -l < "/var/lib/autark/files/$name") new files tracked"
  touch "/sources/.done/blfs-$name"
}

pkg_libaio() {
  sed -i '/install.*libaio.a/s/^/#/' src/Makefile
  make
  make install
}

# [Autark] The test suite is skipped on purpose: it creates real device-mapper devices through the running
# kernel, which in the chroot is the host's, the one holding Autark's own /dev/mapper/autark* volumes.
pkg_lvm2() {
  PATH+=:/usr/sbin                \
  ./configure --prefix=/usr       \
              --enable-cmdlib     \
              --enable-pkgconfig  \
              --enable-udev_sync  &&
  make
  make install
  make install_systemd_units
  sed -e '/locking_dir =/{s/#//;s/var/run/}' \
      -i /etc/lvm/lvm.conf
}

pkg_popt() {
  ./configure --prefix=/usr --disable-static &&
  make
  make check || testfail popt
  make install
}

# [Autark] --no-system-libs instead of BLFS's --system-libs: CMake's bundled copies, since curl, libarchive,
# libuv and nghttp2 aren't on Autark. Its own test suite is skipped (long, and CMake is only a build tool here).
pkg_cmake() {
  sed -i '/"lib64"/s/64//' Modules/GNUInstallDirs.cmake &&

  ./bootstrap --prefix=/usr        \
              --no-system-libs     \
              --mandir=/share/man  \
              --docdir=/share/doc/cmake-4.4.2 &&
  make
  make install
}

pkg_json_c() {
  mkdir build &&
  cd    build &&

  cmake -D CMAKE_INSTALL_PREFIX=/usr \
        -D CMAKE_BUILD_TYPE=Release  \
        -D BUILD_STATIC_LIBS=OFF     \
        .. &&
  make
  make USE_VALGRIND=0 test || testfail json-c
  make install
}

# [Autark] cryptsetup's tests are skipped for the same reason as LVM2's: they drive the host kernel's dm-crypt.
pkg_cryptsetup() {
  ./configure --prefix=/usr       \
              --disable-ssh-token \
              --disable-asciidoc  &&
  make
  make install
}

# [Autark] The tss system user and group that tpm2-tss's udev rules expect (its sysusers.d file isn't applied:
# LFS's systemd is built with sysusers=false).
step_tss_user() {
  getent group tss  > /dev/null || groupadd -r tss
  getent passwd tss > /dev/null || useradd -r -g tss -d /var/lib/tpm -s /usr/bin/false -c "tss user for tpm2" tss
}

# [Autark] Upstream tpm2-tss 4.2.0 (not in BLFS). FAPI off: it needs curl, and systemd uses only ESYS/MU/RC.
# Unit tests need cmocka (not installed), so none are run.
pkg_tpm2_tss() {
  ./configure --prefix=/usr                              \
              --sysconfdir=/etc                          \
              --localstatedir=/var                       \
              --runstatedir=/run                         \
              --disable-static                           \
              --disable-fapi                             \
              --disable-doxygen-doc                      \
              --with-udevrulesdir=/usr/lib/udev/rules.d  \
              --with-udevrulesprefix=60-
  make
  make install
}

# [Autark] pefile from PyPI (not in BLFS), installed the way LFS installs Python modules.
pkg_pefile() {
  pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
  pip3 install --no-index --find-links dist pefile
}

# [Autark] pyelftools from PyPI (not in BLFS): systemd needs it to build systemd-stub, the EFI program ukify
# wraps around the kernel (and which measures the boot image into the TPM).
pkg_pyelftools() {
  pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
  pip3 install --no-index --find-links dist pyelftools
}

# [Autark] systemd rebuilt with LFS chapter 8's options except: ukify, libcryptsetup, tpm2, sysusers and bootloader enabled
# (dracut's journald module, which the whole systemd initramfs needs, requires systemd-sysusers;
# bootloader=enabled builds systemd-stub for ukify; Autark doesn't use systemd-boot itself. The stub embeds
# SBAT metadata naming the distribution, which systemd can't autodetect for a new one).
# machine-id and preset-all were done in chapter 8 and aren't repeated.
pkg_systemd_crypto() {
  sed -e 's/GROUP="render"/GROUP="video"/' \
      -e 's/GROUP="sgx", //'               \
      -i rules.d/50-udev-default.rules.in
  mkdir -p build
  cd       build

  meson setup ..                \
        --prefix=/usr           \
        --buildtype=release     \
        -D default-dnssec=no    \
        -D firstboot=false      \
        -D install-tests=false  \
        -D ldconfig=false       \
        -D sysusers=true        \
        -D rpmmacrosdir=no      \
        -D homed=disabled       \
        -D man=disabled         \
        -D mode=release         \
        -D pamconfdir=no        \
        -D dev-kvm-mode=0660    \
        -D nobody-group=nogroup \
        -D sysupdate=disabled   \
        -D ukify=enabled        \
        -D libcryptsetup=enabled \
        -D tpm2=enabled         \
        -D bootloader=enabled   \
        -D sbat-distro=autark   \
        -D sbat-distro-summary=Autark \
        -D sbat-distro-pkgname=systemd \
        -D sbat-distro-version=261.2 \
        -D sbat-distro-url=https://github.com/Seuketchi/autark \
        -D docdir=/usr/share/doc/systemd-261.2
  ninja
  ninja install
}

run_pkg libaio         libaio-0.3.113.tar.gz    pkg_libaio
run_pkg lvm2           LVM2.2.03.42.tgz         pkg_lvm2
run_pkg popt           popt-1.19.tar.gz         pkg_popt
run_pkg cmake          cmake-4.4.2.tar.gz       pkg_cmake
run_pkg json-c         json-c-0.19.tar.gz       pkg_json_c
run_pkg cryptsetup     cryptsetup-2.8.7.tar.xz  pkg_cryptsetup
run_pkg tss-user       -                        step_tss_user
run_pkg tpm2-tss       tpm2-tss-4.2.0.tar.gz    pkg_tpm2_tss
run_pkg pefile         pefile-2024.8.26.tar.gz  pkg_pefile
run_pkg pyelftools     pyelftools-0.33.tar.gz   pkg_pyelftools
run_pkg systemd-crypto systemd-261.2.tar.gz     pkg_systemd_crypto
echo "== disk encryption and TPM support done"
