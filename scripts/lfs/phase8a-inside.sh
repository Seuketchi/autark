#!/bin/bash
# Phase 8a: the Wayland desktop. Runs INSIDE the chroot as root, started by ch7-chroot.sh with
# INSIDE=phase8a-inside.sh. Builds the BLFS 13.1-systemd closure for Wayfire + foot, plus PAM, networking
# (iwd), Bluetooth, audio (PipeWire) and the fonts. The package list, versions and per-package configure
# decisions are in docs/specs/phase-8a-packages.md; this script is that spec as commands.
#
# Run (from the host):
#   sudo LFS=/mnt/lfs INSIDE=phase8a-inside.sh bash scripts/lfs/ch7-chroot.sh [pkg...]
# With no names it builds everything in order and skips what has a /sources/.done/8a-<name> marker; with names
# (the first column of the run_pkg lines at the bottom, e.g. `mesa wayfire`) it builds only those, in script order.
# Tarballs are expected in /sources (staged from sources-8a/). Names are variables, T_*, just below.
#
# Order: crypto/SSH base → PAM (Linux-PAM, Shadow and systemd rebuilt with it) → OpenSSH → fonts/graphics
# libraries → Wayland → input/KMS → Mesa (LLVM chain) → wlroots/Wayfire → foot → audio/Bluetooth → Wi-Fi.
#
# Commands follow BLFS 13.1-systemd except where marked [Autark]. Deviations from BLFS, all of them:
#  - Wayland-only, no X11: no Xorg libraries, no Xwayland; libxkbcommon/Mesa/xkeyboard-config/Cairo built without
#    X (spec "Skipped on purpose"). BLFS $XORG_PREFIX is /usr.
#  - No GObject-Introspection anywhere (GLib, Pango, WirePlumber), no man pages/docs that need docutils/doxygen.
#  - libxml2 icu=disabled; HarfBuzz without ICU/Graphite; FreeType built twice (without, then with HarfBuzz).
#  - GLib: man-pages=disabled (needs docutils), tests=false; its test suite is not run (it refuses root).
#  - wayland-protocols: the missing `..` in BLFS's meson command added.
#  - libdrm: intel=disabled (libdrm_intel needs libpciaccess; iris doesn't use it).
#  - libseat only (no seatd daemon): -D server=disabled -D libseat-seatd=disabled -D libseat-logind=systemd
#    (BLFS leaves logind on auto; pinned so a missing libsystemd fails the build).
#  - LLVM: targets "host" only (no AMDGPU), no compiler-rt runtime, tests off, 2 parallel link jobs (RAM).
#  - SPIRV-Tools tests skipped (SPIRV_SKIP_TESTS); glslang GLSLANG_TESTS=OFF (needs googletest sources).
#  - Mesa: wayland platform only; gallium iris+llvmpipe, vulkan intel+swrast; no x11/glx/video-codecs/xdemos patch;
#    llvm=enabled pinned; --wrap-mode=nodownload.
#  - libjpeg-turbo: WITH_SIMD=0 (no NASM).
#  - wlroots: backends drm,libinput; renderers gles2; xwayland off; session/libliftoff/color-management pinned
#    to enabled (BLFS leaves them auto); allocators gbm.
#  - Wayfire: system wlroots pinned, tests/xwayland off, --wrap-mode=nodownload; wayfire.ini installed with install -D.
#  - fcft/foot/tllist are upstream (not in BLFS): docs/tests off, grapheme-clustering off, utmp-backend=none.
#  - alsa-lib: --prefix=/usr (BLFS's plain ./configure would use /usr/local); alsa-utils is the optional spec #47.
#  - BlueZ: --disable-manpages --disable-obex (no docutils, no libical).
#  - Lua: hardening flags passed to its Makefile (it overrides CFLAGS), docs not installed.
#  - PipeWire: bluez5/alsa/libsystemd forced on; gstreamer, pulse client, v4l2, jack off; tests off.
#  - WirePlumber: system Lua, introspection/doc/tests off, systemd integration forced on.
#  - Linux-PAM: docs/i18n off. Shadow rebuilt with PAM keeps chapter 8's --disable-logind and
#    --with-group-name-max-length=32. systemd rebuilt with PAM: Autark's pkg_systemd_crypto options exactly,
#    plus pam=enabled and pamconfdir=/etc/pam.d; no `systemctl daemon-reexec` (no running systemd in the chroot).
#  - OpenSSH: --with-pam, PermitRootLogin no; the sshd unit is installed but NOT enabled (firewall blocks all incoming).
#  - make-ca: uses /sources/certdata.txt (-C) if present, else downloads (-g).
#  - Fonts: Geist + Geist Mono (static TTFs) in /usr/share/fonts/geist, DejaVu in /usr/share/fonts/TTF, and an
#    /etc/fonts/local.conf putting Geist first. Python's zipfile unpacks the Geist zip (no unzip in LFS).
#  - iwd and wireless-regdb are upstream; regdb's prebuilt regulatory.db/.p7s are installed without running its Makefile.
#  - libcap's pam_cap, libsndfile and the Vulkan loader (spec optional extras) are not built.
set -euo pipefail

if [ ! -e /sources/wget-list-systemd ] || grep -qi ubuntu /etc/os-release 2>/dev/null; then
  echo "phase8a-inside.sh: not inside the Autark chroot; refusing to run" >&2
  exit 1
fi

logs=/sources/logs
mkdir -p "$logs" /sources/.done /sources/.track /var/lib/autark/files
srcdir=/sources
source "$(dirname "$0")/build-lib.sh"

export CFLAGS="-O2 -march=x86-64-v3 -pipe -fstack-protector-strong -fstack-clash-protection -fcf-protection=full -D_FORTIFY_SOURCE=3"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-Wl,-O1 -Wl,-z,relro -Wl,-z,now"

# Tarball names, in one place. Check against sources-8a/SOURCES.md if a name is wrong.
T_LIBTASN1=libtasn1-4.21.0.tar.gz
T_P11KIT=p11-kit-0.26.5.tar.xz
T_MAKECA=make-ca-1.16.1.tar.gz
T_LINUXPAM=Linux-PAM-1.7.2.tar.xz
T_SHADOW=shadow-4.20.2.tar.xz
T_SYSTEMD=systemd-261.2.tar.gz
T_OPENSSH=openssh-10.5p1.tar.gz
T_SYSTEMDUNITS=blfs-systemd-units-20251204.tar.xz
T_LIBXML2=libxml2-2.15.3.tar.xz
T_LIBPNG=libpng-1.6.58.tar.xz
T_FREETYPE=freetype-2.14.3.tar.xz
T_GLIB=glib-2.88.3.tar.xz
T_HARFBUZZ=harfbuzz-14.3.1.tar.xz
T_FONTCONFIG=fontconfig-2.18.3.tar.xz
T_FRIBIDI=fribidi-1.0.16.tar.xz
T_PIXMAN=pixman-0.46.4.tar.gz
T_CAIRO=cairo-1.18.4.tar.xz
T_PANGO=pango-1.58.2.tar.xz
T_DEJAVU=dejavu-fonts-ttf-2.37.tar.bz2
T_GEIST=geist-font-v1.8.1.zip
T_WAYLAND=wayland-1.26.0.tar.xz
T_WAYLANDPROTOCOLS=wayland-protocols-1.49.tar.xz
T_LIBDRM=libdrm-2.4.134.tar.xz
T_LIBEVDEV=libevdev-1.13.6.tar.xz
T_MTDEV=mtdev-1.1.7.tar.bz2
T_LIBINPUT=libinput-1.31.3.tar.gz
T_XKEYBOARDCONFIG=xkeyboard-config-2.48.tar.xz
T_LIBXKBCOMMON=libxkbcommon-1.13.2.tar.gz
P_LIBXKBCOMMON=libxkbcommon-1.13.2-upstream_fix-1.patch
T_HWDATA=hwdata-0.410.tar.gz
T_LIBDISPLAYINFO=libdisplay-info-0.4.0.tar.xz
T_LIBLIFTOFF=libliftoff-v0.5.0.tar.gz
T_LCMS2=lcms2-2.19.1.tar.gz
T_SEATD=seatd-0.9.3.tar.gz
T_MAKO=mako-1.4.1.tar.gz
T_PYYAML=pyyaml-6.0.3.tar.gz
T_SPIRVHEADERS=SPIRV-Headers-vulkan-sdk-1.4.357.0.tar.gz
T_SPIRVTOOLS=SPIRV-Tools-vulkan-sdk-1.4.357.0.tar.gz
T_GLSLANG=glslang-16.5.0.tar.gz
T_LLVM=llvm-project-22.1.8.src.tar.xz
P_LLVM=llvm-22.1.8-upstream_fix-1.patch
T_SPIRVLLVMTRANSLATOR=SPIRV-LLVM-Translator-22.1.5.tar.gz
T_MESA=mesa-26.1.7.tar.xz
T_YYJSON=yyjson-0.12.0.tar.gz
T_GLM=glm-1.0.3.tar.gz
T_LIBJPEG=libjpeg-turbo-3.2.0.tar.gz
T_WLROOTS=wlroots-0.20.2.tar.bz2
T_WAYFIRE=wayfire-0.11.0.tar.xz
T_TLLIST=tllist-1.1.0.tar.gz
T_FCFT=fcft-3.3.3.tar.gz
T_FOOT=foot-1.28.0.tar.gz
T_ALSALIB=alsa-lib-1.2.16.1.tar.bz2
T_ALSAUCM=alsa-ucm-conf-1.2.16.1.tar.bz2
T_ALSAUTILS=alsa-utils-1.2.16.tar.bz2
T_SBC=sbc-2.2.tar.xz
T_BLUEZ=bluez-5.87.tar.xz
T_LUA=lua-5.4.8.tar.gz
P_LUA=lua-5.4.8-shared_library-1.patch
T_PIPEWIRE=pipewire-1.6.8.tar.bz2
T_WIREPLUMBER=wireplumber-0.5.15.tar.bz2
T_IWD=iwd-3.12.tar.xz
T_REGDB=wireless-regdb-2026.09.03.tar.xz

testfail() { echo "== TESTFAIL: $*"; echo "$(date +%T) $*" >> "$logs/test-failures.txt"; }

# Names given on the command line restrict the run to those packages.
only=" $* "

snapshot() {
  find / -xdev \( -path /sources -o -path /tmp -o -path /root -o -path /var/lib/autark \) -prune \
    -o \( -type f -o -type l \) -print | LC_ALL=C sort
}

run_pkg() {
  local name=$1 tarball=$2 fn=$3
  if [ "$only" != "  " ]; then
    case "$only" in *" $name "*) ;; *) return ;; esac
  fi
  if [ -e "/sources/.done/8a-$name" ]; then echo "== $name: already done, skipped"; return; fi
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
  touch "/sources/.done/8a-$name"
}

# ---- Crypto and trust store ----

pkg_libtasn1() {
  ./configure --prefix=/usr --disable-static
  make
  { make check; } || testfail libtasn1
  make install
}

# The anchor hook makes `trust extract-compat` (update-ca-certificates) call make-ca, which owns the stores.
pkg_p11_kit() {
  sed '20,$ d' -i trust/trust-extract-compat
  cat >> trust/trust-extract-compat << "EOF"
# Copy existing anchor modifications to /etc/ssl/local
/usr/libexec/make-ca/copy-trust-modifications
# Update trust stores
/usr/sbin/make-ca -r
EOF
  mkdir p11-build
  cd    p11-build
  meson setup ..            \
        --prefix=/usr       \
        --buildtype=release \
        -D trust_paths=/etc/pki/anchors
  ninja
  { ninja test; } || testfail p11-kit
  ninja install
  ln -sfv /usr/libexec/p11-kit/trust-extract-compat /usr/bin/update-ca-certificates
}

# [Autark] No curl needed: make-ca downloads certdata.txt with `openssl s_client`. If /sources/certdata.txt exists
# it is used as-is (-C), so the build can run offline.
# certdata.txt is staged with the sources (downloaded once, sha256 in sources-8a/SOURCES.md), never fetched here.
pkg_make_ca() {
  sed '/mktemp/s/-t //' -i make-ca
  make install
  install -vdm755 /etc/ssl/local
  [ -s "$srcdir/certdata.txt" ] || { echo "certdata.txt missing from /sources"; return 1; }
  /usr/sbin/make-ca -C "$srcdir/certdata.txt"
  systemctl enable update-pki.timer
}

# ---- PAM: Linux-PAM, then Shadow and systemd rebuilt with it ----

# [Autark] docs=disabled i18n=disabled: no docbook/xsltproc here. The tests need a permissive /etc/pam.d/other
# for a first install; it is replaced by BLFS's restrictive one below.
pkg_linux_pam() {
  mkdir build
  cd    build
  meson setup ..        \
    --prefix=/usr       \
    --buildtype=release \
    -D docs=disabled    \
    -D i18n=disabled    \
    -D docdir=/usr/share/doc/Linux-PAM-1.7.2
  ninja
  install -v -m755 -d /etc/pam.d
  if [ ! -e /etc/pam.d/other ]; then
    cat > /etc/pam.d/other << "EOF"
auth     required       pam_deny.so
account  required       pam_deny.so
password required       pam_deny.so
session  required       pam_deny.so
EOF
    { ninja test; } || testfail linux-pam
    rm -fv /etc/pam.d/other
  else
    { ninja test; } || testfail linux-pam
  fi
  ninja install
  chmod -v 4755 /usr/sbin/unix_chkpwd

  cat > /etc/pam.d/system-account << "EOF"
# Begin /etc/pam.d/system-account
account   required    pam_unix.so
# End /etc/pam.d/system-account
EOF
  cat > /etc/pam.d/system-auth << "EOF"
# Begin /etc/pam.d/system-auth
auth      required    pam_unix.so
# End /etc/pam.d/system-auth
EOF
  cat > /etc/pam.d/system-session << "EOF"
# Begin /etc/pam.d/system-session
session   required    pam_unix.so
# End /etc/pam.d/system-session
EOF
  cat > /etc/pam.d/system-password << "EOF"
# Begin /etc/pam.d/system-password
# use yescrypt hash for encryption, use shadow, and try to use any
# previously defined authentication token (chosen password) set by any
# prior module.
password  required    pam_unix.so       yescrypt shadow try_first_pass
# End /etc/pam.d/system-password
EOF
  cat > /etc/pam.d/other << "EOF"
# Begin /etc/pam.d/other
auth        required        pam_warn.so
auth        required        pam_deny.so
account     required        pam_warn.so
account     required        pam_deny.so
password    required        pam_warn.so
password    required        pam_deny.so
session     required        pam_warn.so
session     required        pam_deny.so
# End /etc/pam.d/other
EOF
}

# [Autark] Chapter 8's Shadow options kept (--disable-logind, --with-group-name-max-length=32); pwconv, grpconv and
# `useradd -D` are not repeated. BLFS's PAM files for login, passwd, su, chpasswd, newusers, chage and the other
# shadow tools follow the rebuild. Without them every Shadow program that now links PAM would refuse to work,
# including login: this step must finish before the image is booted.
# Reviewed: BLFS intends `make install` to rewrite /etc/login.defs (then PAM-handled settings are commented out
# below); /etc/default/useradd isn't installed by make install, so ch8's file stays.
# not read shadow's etc/Makefile.am); the loop below is idempotent either way, but useradd's chapter 8 defaults
# (--gid 999, no mail spool) would be lost if it overwrites.
pkg_shadow_pam() {
  find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
  find man -name Makefile.in -exec sed -i 's/passwd\.5 / /'   {} \;
  sed -e 's:#ENCRYPT_METHOD SHA512:ENCRYPT_METHOD YESCRYPT:' \
      -e 's:/var/spool/mail:/var/mail:'                      \
      -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                     \
      -i etc/login.defs
  ./configure --sysconfdir=/etc   \
              --disable-static    \
              --with-{b,yes}crypt \
              --without-libbsd    \
              --disable-logind    \
              --with-group-name-max-length=32
  make
  make exec_prefix=/usr pamddir= install

  # Login-time work that PAM modules do now.
  install -v -m644 /etc/login.defs /etc/login.defs.orig
  for FUNCTION in FAIL_DELAY               \
                  FAILLOG_ENAB             \
                  LASTLOG_ENAB             \
                  MAIL_CHECK_ENAB          \
                  OBSCURE_CHECKS_ENAB      \
                  PORTTIME_CHECKS_ENAB     \
                  QUOTAS_ENAB              \
                  CONSOLE MOTD_FILE        \
                  FTMP_FILE NOLOGINS_FILE  \
                  ENV_HZ PASS_MIN_LEN      \
                  SU_WHEEL_ONLY            \
                  PASS_CHANGE_TRIES        \
                  PASS_ALWAYS_WARN         \
                  CHFN_AUTH ENCRYPT_METHOD \
                  ENVIRON_FILE
  do
    sed -i "s/^${FUNCTION}/# &/" /etc/login.defs
  done

  cat > /etc/pam.d/login << "EOF"
# Begin /etc/pam.d/login
# Set failure delay before next prompt to 3 seconds
auth      optional    pam_faildelay.so  delay=3000000
# Check to make sure that the user is allowed to login
auth      requisite   pam_nologin.so
# Check to make sure that root is allowed to login
# Disabled by default. You will need to create /etc/securetty
# file for this module to function. See man 5 securetty.
#auth      required    pam_securetty.so
# Additional group memberships - disabled by default
#auth      optional    pam_group.so
# include system auth settings
auth      include     system-auth
# check access for the user
account   required    pam_access.so
# include system account settings
account   include     system-account
# Set default environment variables for the user
session   required    pam_env.so
# Set resource limits for the user
session   required    pam_limits.so
# Display the message of the day - Disabled by default
#session   optional    pam_motd.so
# Check user's mail - Disabled by default
#session   optional    pam_mail.so      standard quiet
# include system session and password settings
session   include     system-session
password  include     system-password
# End /etc/pam.d/login
EOF
  cat > /etc/pam.d/passwd << "EOF"
# Begin /etc/pam.d/passwd
password  include     system-password
# End /etc/pam.d/passwd
EOF
  cat > /etc/pam.d/su << "EOF"
# Begin /etc/pam.d/su
# always allow root
auth      sufficient  pam_rootok.so
# Allow users in the wheel group to execute su without a password
# disabled by default
#auth      sufficient  pam_wheel.so trust use_uid
# include system auth settings
auth      include     system-auth
# limit su to users in the wheel group
# disabled by default
#auth      required    pam_wheel.so use_uid
# include system account settings
account   include     system-account
# Set default environment variables for the service user
session   required    pam_env.so
# include system session settings
session   include     system-session
# End /etc/pam.d/su
EOF
  cat > /etc/pam.d/chpasswd << "EOF"
# Begin /etc/pam.d/chpasswd
# always allow root
auth      sufficient  pam_rootok.so
# include system auth and account settings
auth      include     system-auth
account   include     system-account
password  include     system-password
# End /etc/pam.d/chpasswd
EOF
  sed -e s/chpasswd/newusers/ /etc/pam.d/chpasswd > /etc/pam.d/newusers
  cat > /etc/pam.d/chage << "EOF"
# Begin /etc/pam.d/chage
# always allow root
auth      sufficient  pam_rootok.so
# include system auth and account settings
auth      include     system-auth
account   include     system-account
# End /etc/pam.d/chage
EOF
  for PROGRAM in chfn chgpasswd chsh groupadd groupdel \
                 groupmems groupmod useradd userdel usermod
  do
    install -v -m644 /etc/pam.d/chage /etc/pam.d/${PROGRAM}
    sed -i "s/chage/$PROGRAM/" /etc/pam.d/${PROGRAM}
  done

  # PAM modules replace these two files.
  if [ -f /etc/login.access ]; then mv -v /etc/login.access /etc/login.access.NOUSE; fi
  if [ -f /etc/limits ]; then mv -v /etc/limits /etc/limits.NOUSE; fi
}

# [Autark] Autark's pkg_systemd_crypto meson line unchanged except pamconfdir=/etc/pam.d and the added pam=enabled.
# Then BLFS's logind PAM setup: pam_systemd in system-session (so a login registers a logind session and gets
# /run/user/UID), the systemd-user service's own PAM stack, and the user-environment generator that hands
# /etc/profile's variables to the per-user systemd instance.
pkg_systemd_pam() {
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
        -D pam=enabled          \
        -D pamconfdir=/etc/pam.d \
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

  grep -q pam_systemd /etc/pam.d/system-session || cat >> /etc/pam.d/system-session << "EOF"
# Begin Systemd addition
session  required    pam_loginuid.so
session  optional    pam_systemd.so
# End Systemd addition
EOF
  cat > /etc/pam.d/systemd-user << "EOF"
# Begin /etc/pam.d/systemd-user
account  required    pam_access.so
account  include     system-account
session  required    pam_env.so
session  required    pam_limits.so
session  required    pam_loginuid.so
session  optional    pam_keyinit.so force revoke
session  optional    pam_systemd.so
auth     required    pam_deny.so
password required    pam_deny.so
# End /etc/pam.d/systemd-user
EOF
  install -vdm755 /etc/systemd/user-environment-generators
  cat > /etc/systemd/user-environment-generators/50-profile.sh << "EOF"
#!/usr/bin/env -S -i /usr/bin/bash
# SPDX-License-Identifier: MIT
. /etc/profile
# Systemd should have already set a better value for them.
unset XDG_RUNTIME_DIR
for i in $(locale); do
  unset ${i%=*}
done
# Some shell magic that we don't want to expose.
unset SHLVL
# Systemd does not want to pass functions to the environment
for i in $(declare -pF | awk '{print $3}'); do
  unset -f $i
done
python3 << _EOF
import os
for var in os.environ:
  # Simply unsetting them in shell does not work.
  if var in ['LC_CTYPE', '_']:
    continue
  print(var + '=' + os.environ[var])
_EOF
EOF
  chmod -v 755 /etc/systemd/user-environment-generators/50-profile.sh
}

# ---- OpenSSH ----

# [Autark] --with-pam (the BLFS PAM option); sshd's PAM file is copied from login's, as BLFS says. The build's own
# test suite is skipped (long; it starts a real sshd on loopback). Root login is off (BLFS's recommendation).
# Reviewed: keys only (PasswordAuthentication/KbdInteractiveAuthentication no, PermitRootLogin no); sshd not enabled.
# not enabled, so nothing listens; decide PasswordAuthentication/KbdInteractiveAuthentication before enabling it.
pkg_openssh() {
  install -v -g sys -m700 -d /var/lib/sshd
  getent group sshd  > /dev/null || groupadd -g 50 sshd
  getent passwd sshd > /dev/null || useradd -c 'sshd PrivSep' -d /var/lib/sshd -g sshd -s /bin/false -u 50 sshd

  ./configure --prefix=/usr                            \
              --sysconfdir=/etc/ssh                    \
              --with-privsep-path=/var/lib/sshd        \
              --with-default-path=/usr/bin             \
              --with-superuser-path=/usr/sbin:/usr/bin \
              --with-pid-dir=/run                      \
              --with-pam
  make
  make install
  install -v -m755    contrib/ssh-copy-id /usr/bin
  install -v -m644    contrib/ssh-copy-id.1 /usr/share/man/man1
  install -v -m755 -d /usr/share/doc/openssh-10.5p1
  install -v -m644    INSTALL LICENCE OVERVIEW README* /usr/share/doc/openssh-10.5p1

  grep -q '^PermitRootLogin no' /etc/ssh/sshd_config || echo "PermitRootLogin no" >> /etc/ssh/sshd_config
  sed 's@d/login@d/sshd@g' /etc/pam.d/login > /etc/pam.d/sshd
  chmod 644 /etc/pam.d/sshd
  grep -q '^UsePAM yes' /etc/ssh/sshd_config || echo "UsePAM yes" >> /etc/ssh/sshd_config
  # [Autark] Keys only. sshd stays disabled, and the firewall drops incoming connections anyway.
  grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config || echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
  grep -q '^KbdInteractiveAuthentication no' /etc/ssh/sshd_config || echo "KbdInteractiveAuthentication no" >> /etc/ssh/sshd_config
}

# [Autark] Installed, not enabled: `systemctl enable sshd.service` when remote access is wanted.
pkg_sshd_unit() {
  make install-sshd
}

# ---- Fonts and 2D graphics libraries ----

# [Autark] icu=disabled (BLFS: enabled).
pkg_libxml2() {
  sed -i "/'git'/,+3d" meson.build
  mkdir build
  cd    build
  meson setup ..            \
        --prefix=/usr       \
        --buildtype=release \
        -D history=enabled  \
        -D icu=disabled
  ninja
  ninja install
}

# [Autark] APNG patch skipped (browser-only).
pkg_libpng() {
  ./configure --prefix=/usr --disable-static
  make
  { make check; } || testfail libpng
  make install
  install -vDm644 README libpng-manual.txt -t /usr/share/doc/libpng-1.6.58
}

# FreeType is circular with HarfBuzz (HarfBuzz wants FreeType; FreeType wants HarfBuzz for auto-hinting), so it
# is built twice: pass 1 --without-harfbuzz, pass 2 (after HarfBuzz) with BLFS's --with-harfbuzz=dynamic.
freetype_build() {
  sed -ri "s:.*(AUX_MODULES.*valid):\1:" modules.cfg
  sed -r "s:.*(#.*SUBPIXEL_RENDERING) .*:\1:" \
      -i include/freetype/config/ftoption.h
  ./configure --prefix=/usr            \
              --disable-static         \
              --enable-freetype-config \
              "$1"
  make
  make install
}

pkg_freetype_pass1() {
  freetype_build --without-harfbuzz
}

pkg_freetype_pass2() {
  freetype_build --with-harfbuzz=dynamic
}

# [Autark] No introspection, no man pages (docutils), tests not built. The test suite needs a non-root user, so
# it is not run.
pkg_glib() {
  mkdir build
  cd    build
  meson setup ..                  \
        --prefix=/usr             \
        --buildtype=release       \
        -D introspection=disabled \
        -D glib_debug=disabled    \
        -D man-pages=disabled     \
        -D sysprof=disabled       \
        -D tests=false
  ninja
  ninja install
}

# [Autark] No Graphite, no ICU, no introspection, no docs (BLFS enables graphite2).
pkg_harfbuzz() {
  mkdir build
  cd    build
  meson setup ..                  \
        --prefix=/usr             \
        --buildtype=release       \
        -D graphite2=disabled     \
        -D icu=disabled           \
        -D introspection=disabled \
        -D docs=disabled
  ninja
  { ninja test; } || testfail harfbuzz
  ninja install
}

# Fontconfig's own tests are skipped: one needs user namespaces, some download fonts.
pkg_fontconfig() {
  ./configure --prefix=/usr        \
              --sysconfdir=/etc    \
              --localstatedir=/var \
              --disable-docs       \
              --docdir=/usr/share/doc/fontconfig-2.18.3
  make
  make install
}

pkg_fribidi() {
  mkdir build
  cd    build
  meson setup --prefix=/usr --buildtype=release ..
  ninja
  { ninja test; } || testfail fribidi
  ninja install
}

pkg_pixman() {
  mkdir build
  cd    build
  meson setup --prefix=/usr --buildtype=release ..
  ninja
  { ninja test; } || testfail pixman
  ninja install
}

# [Autark] Tests off (BLFS: "no working test suite"). With no Xorg libraries the X backends stay off.
pkg_cairo() {
  mkdir build
  cd    build
  meson setup --prefix=/usr --buildtype=release -D tests=disabled ..
  ninja
  ninja install
}

# [Autark] introspection=disabled (BLFS: enabled). Its test suite is skipped: two tests fail by design without
# font data, and the fonts arrive after this.
pkg_pango() {
  mkdir build
  cd    build
  meson setup --prefix=/usr             \
              --buildtype=release       \
              --wrap-mode=nofallback    \
              -D introspection=disabled \
              ..
  ninja
  ninja install
}

# DejaVu is the fallback face (spec #16); Geist is the primary one (step_geist). Without any font file foot and
# Wayfire render no text. The font tarball is not built, only unpacked into place.
pkg_dejavu() {
  install -vDm644 -t /usr/share/fonts/TTF ttf/*.ttf
  install -vDm644 -t /usr/share/doc/dejavu-fonts-ttf-2.37 LICENSE AUTHORS README.md
}

# [Autark] Geist (sans) and Geist Mono, the static TTFs only (the zip also holds OTF and variable copies of the same
# families; installing all of them makes fontconfig list every face three times). Python's zipfile does the
# unpacking: LFS has no unzip. /etc/fonts/local.conf, read by fontconfig's 51-local.conf, puts Geist first and
# leaves DejaVu behind it for glyphs Geist lacks.
# Decided: Geist + Geist Mono first (decisions.md), DejaVu as fallback for scripts Geist doesn't cover.
step_geist() {
  install -vdm755 /usr/share/fonts/geist /usr/share/licenses/geist-font
  python3 -I - "$srcdir/$T_GEIST" << "EOF"
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
for name in z.namelist():
    if name.startswith(('geist-font/Geist/ttf/', 'geist-font/GeistMono/ttf/')) and name.endswith('.ttf'):
        with open('/usr/share/fonts/geist/' + name.rsplit('/', 1)[1], 'wb') as f:
            f.write(z.read(name))
    elif name == 'geist-font/OFL.txt':
        with open('/usr/share/licenses/geist-font/OFL.txt', 'wb') as f:
            f.write(z.read(name))
EOF
  chmod 644 /usr/share/fonts/geist/*.ttf
  cat > /etc/fonts/local.conf << "EOF"
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <alias>
    <family>sans-serif</family>
    <prefer><family>Geist</family><family>DejaVu Sans</family></prefer>
  </alias>
  <alias>
    <family>monospace</family>
    <prefer><family>Geist Mono</family><family>DejaVu Sans Mono</family></prefer>
  </alias>
</fontconfig>
EOF
  fc-cache -f
}

# ---- Wayland, input, display ----

pkg_wayland() {
  mkdir build
  cd    build
  meson setup ..               \
        --prefix=/usr          \
        --buildtype=release    \
        -D documentation=false
  ninja
  { env -u XDG_RUNTIME_DIR ninja test; } || testfail wayland
  ninja install
}

# [Autark] BLFS's command has no `..` (source directory) at the end; meson fails without it.
pkg_wayland_protocols() {
  mkdir build
  cd    build
  meson setup --prefix=/usr --buildtype=release ..
  ninja
  { ninja test; } || testfail wayland-protocols
  ninja install
}

# [Autark] intel=disabled: libdrm_intel needs libpciaccess and only Mesa's i915 driver uses it, not iris.
# Its tests are skipped (they want a DRM device).
pkg_libdrm() {
  mkdir build
  cd    build
  meson setup --prefix=/usr         \
              --buildtype=release   \
              -D udev=true          \
              -D valgrind=disabled  \
              -D intel=disabled     \
              ..
  ninja
  ninja install
}

pkg_libevdev() {
  mkdir build
  cd    build
  meson setup ..                  \
        --prefix=/usr             \
        --buildtype=release       \
        -D documentation=disabled \
        -D tests=disabled
  ninja
  ninja install
}

pkg_mtdev() {
  ./configure --prefix=/usr --disable-static
  make
  make install
}

# BLFS's tests=false (the test suite needs pytest and many devices).
pkg_libinput() {
  mkdir build
  cd    build
  meson setup ..                   \
        --prefix=/usr              \
        --buildtype=release        \
        -D debug-gui=false         \
        -D tests=false             \
        -D libwacom=false          \
        -D udev-dir=/usr/lib/udev
  ninja
  ninja install
}

# Data only; BLFS lists Xorg Libraries as required but its meson.build needs no library (spec). Its tests are skipped.
pkg_xkeyboard_config() {
  mkdir build
  cd    build
  meson setup --prefix=/usr --buildtype=release ..
  ninja
  ninja install
}

# [Autark] enable-x11=false (Wayland only). Tests need Xvfb, so none are run.
pkg_libxkbcommon() {
  patch -Np1 -i "$srcdir/$P_LIBXKBCOMMON"
  mkdir build
  cd    build
  meson setup ..               \
        --prefix=/usr          \
        --buildtype=release    \
        -D enable-docs=false   \
        -D enable-x11=false
  ninja
  ninja install
}

pkg_hwdata() {
  ./configure --prefix=/usr --disable-blacklist
  make install
}

pkg_libdisplay_info() {
  mkdir build
  cd    build
  meson setup --prefix=/usr --buildtype=release ..
  ninja
  { ninja test; } || testfail libdisplay-info
  ninja install
}

pkg_libliftoff() {
  mkdir build
  cd    build
  meson setup --prefix=/usr --buildtype=release ..
  ninja
  { ninja test; } || testfail libliftoff
  ninja install
}

pkg_lcms2() {
  mkdir build
  cd    build
  meson setup --prefix=/usr --buildtype=release ..
  ninja
  { ninja test; } || testfail lcms2
  ninja install
}

# [Autark] libseat only: no seatd daemon, no built-in server; sessions come from systemd-logind (which is why
# PAM comes first). libseat-logind=systemd instead of auto so a missing libsystemd fails here, not at login.
pkg_seatd() {
  mkdir build
  cd    build
  meson setup --prefix=/usr                 \
              --buildtype=release           \
              -D server=disabled            \
              -D libseat-seatd=disabled     \
              -D libseat-logind=systemd     \
              -D man-pages=disabled         \
              ..
  ninja
  { ninja test; } || testfail seatd
  ninja install
}

# ---- Mesa and its build-time chain ----

# Mako and PyYAML: Mesa's build scripts. The wheel is built and installed the way LFS installs Python modules.
# Note: pure-Python PyYAML (no Cython/libyaml); if setup.py insists on Cython, that shows up as a build failure.
# add Cython or pass --global-option --without-libyaml.
pkg_mako() {
  pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
  pip3 install --no-index --find-links dist --no-user Mako
}

pkg_pyyaml() {
  pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
  pip3 install --no-index --find-links dist --no-user PyYAML
}

pkg_spirv_headers() {
  mkdir build
  cd    build
  cmake -D CMAKE_INSTALL_PREFIX=/usr -G Ninja ..
  ninja
  ninja install
}

# [Autark] SPIRV_SKIP_TESTS=ON: its tests need googletest/effcee sources, which are not staged.
pkg_spirv_tools() {
  mkdir build
  cd    build
  cmake -D CMAKE_INSTALL_PREFIX=/usr     \
        -D CMAKE_BUILD_TYPE=Release      \
        -D SPIRV_WERROR=OFF              \
        -D BUILD_SHARED_LIBS=ON          \
        -D SPIRV_TOOLS_BUILD_STATIC=OFF  \
        -D SPIRV-Headers_SOURCE_DIR=/usr \
        -D SPIRV_SKIP_TESTS=ON           \
        -G Ninja ..
  ninja
  ninja install
}

# [Autark] GLSLANG_TESTS=OFF (BLFS: ON): the tests want googletest, fetched by a script that needs network.
# Mesa's anv needs glslangValidator.
pkg_glslang() {
  mkdir build
  cd    build
  cmake -D CMAKE_INSTALL_PREFIX=/usr     \
        -D CMAKE_BUILD_TYPE=Release      \
        -D ALLOW_EXTERNAL_SPIRV_TOOLS=ON \
        -D BUILD_SHARED_LIBS=ON          \
        -D GLSLANG_TESTS=OFF             \
        -G Ninja ..
  ninja
  ninja install
}

# [Autark] Needed only for Mesa's mesa_clc build tool (iris and anv). Narrower than BLFS: LLVM_TARGETS_TO_BUILD="host"
# (no AMDGPU), no compiler-rt runtime (only rustc wants it), LLVM_INCLUDE_TESTS=OFF (their test suite is 23 GB and
# is not run), LLVM_PARALLEL_LINK_JOBS=2 (each link step of libLLVM/libclang-cpp can take several GB of RAM).
# BLFS's clang cfg files are created before the build: -fstack-protector-strong by default, like GCC here.
pkg_llvm() {
  patch -Np1 -i "$srcdir/$P_LLVM"
  grep -rl '#!.*python$' | xargs sed -i '1s/python$/python3/'
  mkdir -pv /etc/clang
  for i in clang clang++; do
    echo -fstack-protector-strong > /etc/clang/$i.cfg
  done

  mkdir -v llvm/build
  cd       llvm/build
  CC=gcc CXX=g++                               \
  cmake -D CMAKE_INSTALL_PREFIX=/usr           \
        -D CMAKE_SKIP_INSTALL_RPATH=ON         \
        -D LLVM_ENABLE_FFI=ON                  \
        -D CMAKE_BUILD_TYPE=Release            \
        -D LLVM_BUILD_LLVM_DYLIB=ON            \
        -D LLVM_LINK_LLVM_DYLIB=ON             \
        -D LLVM_ENABLE_RTTI=ON                 \
        -D LLVM_TARGETS_TO_BUILD="host"        \
        -D LLVM_ENABLE_PROJECTS=clang          \
        -D LLVM_BINUTILS_INCDIR=/usr/include   \
        -D LLVM_INCLUDE_BENCHMARKS=OFF         \
        -D LLVM_INCLUDE_TESTS=OFF              \
        -D LLVM_PARALLEL_LINK_JOBS=2           \
        -D CLANG_DEFAULT_PIE_ON_LINUX=ON       \
        -D CLANG_CONFIG_FILE_SYSTEM_DIR=/etc/clang \
        -W no-author -G Ninja ..
  ninja
  ninja install
}

# Must match LLVM's major.minor (22.1).
pkg_spirv_llvm_translator() {
  mkdir build
  cd    build
  cmake -D CMAKE_INSTALL_PREFIX=/usr                   \
        -D CMAKE_BUILD_TYPE=Release                    \
        -D BUILD_SHARED_LIBS=ON                        \
        -D CMAKE_SKIP_INSTALL_RPATH=ON                 \
        -D LLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR=/usr \
        -G Ninja ..
  ninja
  ninja install
}

# [Autark] Wayland only; gallium iris (Intel iGPU) + llvmpipe, vulkan intel (anv) + swrast (lavapipe), so Wayfire also
# starts in QEMU (needs kernel DRM_VGEM). No x11, glx, video-codecs=all or xdemos patch (BLFS). llvm=enabled is
# pinned so a missing LLVM fails the build instead of silently dropping llvmpipe/lavapipe. No tests.
pkg_mesa() {
  mkdir build
  cd    build
  meson setup ..                     \
        --prefix=/usr                \
        --buildtype=release          \
        --wrap-mode=nodownload       \
        -D platforms=wayland         \
        -D gallium-drivers=iris,llvmpipe \
        -D vulkan-drivers=intel,swrast   \
        -D llvm=enabled              \
        -D glx=disabled              \
        -D valgrind=disabled         \
        -D libunwind=disabled
  ninja
  ninja install
}

# ---- Compositor ----

# Wayfire's wf-json subproject would git-clone this at configure time otherwise.
pkg_yyjson() {
  mkdir build
  cd    build
  cmake -D CMAKE_INSTALL_PREFIX=/usr \
        -D CMAKE_BUILD_TYPE=Release  \
        -D BUILD_SHARED_LIBS=ON      \
        -D YYJSON_BUILD_TESTS=ON     \
        -G Ninja ..
  ninja
  { ninja test; } || testfail yyjson
  ninja install
}

# Headers only. Documentation not installed.
pkg_glm() {
  cp -r glm /usr/include/
}

# [Autark] WITH_SIMD=0: NASM is not built, and the SIMD code would need it.
pkg_libjpeg() {
  mkdir build
  cd    build
  cmake -D CMAKE_INSTALL_PREFIX=/usr        \
        -D CMAKE_BUILD_TYPE=RELEASE         \
        -D ENABLE_STATIC=FALSE              \
        -D CMAKE_INSTALL_DEFAULT_LIBDIR=lib \
        -D CMAKE_SKIP_INSTALL_RPATH=ON      \
        -D CMAKE_INSTALL_DOCDIR=/usr/share/doc/libjpeg-turbo-3.2.0 \
        -D WITH_SIMD=0                      \
        ..
  make
  { make test; } || testfail libjpeg-turbo
  make install
}

# [Autark] Backends/renderer chosen explicitly (Wayfire hard-requires drm, session and libinput); session,
# libliftoff and color-management pinned to enabled so a missing dependency fails the build. xwayland off, no examples.
pkg_wlroots() {
  mkdir build
  cd    build
  meson setup --prefix=/usr                \
              --buildtype=release          \
              --wrap-mode=nofallback       \
              -D xwayland=disabled         \
              -D examples=false            \
              -D backends=drm,libinput     \
              -D renderers=gles2           \
              -D allocators=gbm            \
              -D session=enabled           \
              -D libliftoff=enabled        \
              -D color-management=enabled  \
              ..
  ninja
  ninja install
}

# [Autark] System wlroots (0.20.x) instead of the vendored copy; --wrap-mode=nodownload so nothing is fetched. After
# install BLFS removes three static libraries and copies the default wayfire.ini.
pkg_wayfire() {
  mkdir build
  cd    build
  meson setup --prefix=/usr                 \
              --buildtype=release           \
              --wrap-mode=nodownload        \
              -D use_system_wlroots=enabled \
              -D xwayland=disabled          \
              -D tests=disabled             \
              ..
  ninja
  ninja install
  rm -vf /usr/lib/libwftouch.a \
         /usr/lib/libwayfire-{move-drag-interface,workspace-wall}.a
  install -vDm644 ../wayfire.ini /usr/share/wayfire/wayfire.ini
}

# ---- Terminal (upstream, not in BLFS: codeberg dnkl) ----

pkg_tllist() {
  meson setup build --prefix=/usr --buildtype=release
  ninja -C build
  { ninja -C build test; } || testfail tllist
  ninja -C build install
}

# [Autark] HarfBuzz shaping of grapheme clusters only (run-shaping off); bundled nanosvg; no docs.
pkg_fcft() {
  meson setup build                 \
        --prefix=/usr               \
        --buildtype=release         \
        --wrap-mode=nodownload      \
        -D docs=disabled            \
        -D run-shaping=disabled     \
        -D grapheme-shaping=enabled
  ninja -C build
  ninja -C build install
}

# [Autark] No docs/scdoc, no libutf8proc (grapheme clustering off), no tests, utmp-backend=none (libutempter is not
# built, so the default helper path would point at nothing). Terminfo is built with ncurses' tic.
pkg_foot() {
  meson setup build                         \
        --prefix=/usr                       \
        --buildtype=release                 \
        --wrap-mode=nodownload              \
        -D docs=disabled                    \
        -D grapheme-clustering=disabled     \
        -D tests=false                      \
        -D utmp-backend=none
  ninja -C build
  ninja -C build install
}

# ---- Audio and Bluetooth ----

# [Autark] --prefix=/usr (BLFS's plain ./configure installs to /usr/local, where PipeWire's pkg-config would not
# look). ucm-conf goes into /usr/share/alsa as BLFS says.
pkg_alsa_lib() {
  ./configure --prefix=/usr
  make
  make install
  tar -C /usr/share/alsa --strip-components=1 -xf "$srcdir/$T_ALSAUCM"
}

# Optional (spec #47): aplay, alsamixer, speaker-test for debugging.
pkg_alsa_utils() {
  ./configure --prefix=/usr          \
              --disable-alsaconf     \
              --disable-bat          \
              --disable-xmlto        \
              --with-curses=ncursesw
  make
  make install
}

pkg_sbc() {
  ./configure --prefix=/usr --disable-static --disable-tester
  make
  make install
}

# [Autark] --disable-manpages (configure hard-fails without rst2man) and --disable-obex (the only libical user).
pkg_bluez() {
  ./configure --prefix=/usr         \
              --sysconfdir=/etc     \
              --localstatedir=/var  \
              --enable-library      \
              --disable-manpages    \
              --disable-obex
  make
  { make check; } || testfail bluez
  make install
  ln -svf ../libexec/bluetooth/bluetoothd /usr/sbin
  install -v -dm555 /etc/bluetooth
  install -v -m644 src/main.conf /etc/bluetooth/main.conf
}

# [Autark] Lua's Makefile sets its own CFLAGS, so the hardening flags go in through MYCFLAGS/MYLDFLAGS. Built
# because WirePlumber's alternative is a Lua subproject it would download. Docs not installed.
pkg_lua() {
  cat > lua.pc << "EOF"
V=5.4
R=5.4.8
prefix=/usr
INSTALL_BIN=${prefix}/bin
INSTALL_INC=${prefix}/include
INSTALL_LIB=${prefix}/lib
INSTALL_MAN=${prefix}/share/man/man1
INSTALL_LMOD=${prefix}/share/lua/${V}
INSTALL_CMOD=${prefix}/lib/lua/${V}
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include
Name: Lua
Description: An Extensible Extension Language
Version: ${R}
Requires:
Libs: -L${libdir} -llua -lm -ldl
Cflags: -I${includedir}
EOF
  patch -Np1 -i "$srcdir/$P_LUA"
  make linux MYCFLAGS="$CFLAGS" MYLDFLAGS="$LDFLAGS"
  make INSTALL_TOP=/usr                \
       INSTALL_DATA="cp -d"            \
       INSTALL_MAN=/usr/share/man/man1 \
       TO_LIB="liblua.so liblua.so.5.4 liblua.so.5.4.8" \
       install
  install -v -m644 -D lua.pc /usr/lib/pkgconfig/lua.pc
}

# [Autark] bluez5/alsa/libsystemd forced on so a missing dependency fails the build; no GStreamer, PulseAudio
# client, V4L2 or JACK (PipeWire has its own PulseAudio server module); tests off (they need a running daemon).
# Its user units (pipewire.socket, pipewire-pulse.socket) are installed but not enabled.
pkg_pipewire() {
  mkdir build
  cd    build
  meson setup ..                                  \
        --prefix=/usr                             \
        --buildtype=release                       \
        -D session-managers="[]"                  \
        -D bluez5=enabled                         \
        -D alsa=enabled                           \
        -D libsystemd=enabled                     \
        -D systemd-user-service=enabled           \
        -D gstreamer=disabled                     \
        -D gstreamer-device-provider=disabled     \
        -D libpulse=disabled                      \
        -D v4l2=disabled                          \
        -D pipewire-v4l2=disabled                 \
        -D tests=disabled
  ninja
  ninja install
}

# [Autark] System Lua, no introspection/docs/tests, systemd integration pinned (installs the user unit). BLFS then
# renames the doc directory; docs are off here, so only if it exists.
pkg_wireplumber() {
  mkdir build
  cd    build
  meson setup --prefix=/usr             \
              --buildtype=release       \
              -D system-lua=true        \
              -D introspection=disabled \
              -D doc=disabled           \
              -D tests=false            \
              -D dbus-tests=false       \
              -D systemd=enabled        \
              -D elogind=disabled       \
              ..
  ninja
  ninja install
  if [ -d /usr/share/doc/wireplumber ]; then mv -v /usr/share/doc/wireplumber /usr/share/doc/wireplumber-0.5.15; fi
}

# ---- Wi-Fi (upstream, not in BLFS) ----

# iwd bundles ELL (no separate package). EnableNetworkConfiguration stays off: systemd-networkd does DHCP. Its
# test suite is skipped (needs kernel crypto/mac80211_hwsim).
pkg_iwd() {
  ./configure --prefix=/usr \
              --sysconfdir=/etc \
              --localstatedir=/var
  make
  make install
}

# Data only. The release tarball already contains the signed regulatory.db and regulatory.db.p7s; installing them
# directly avoids the Makefile, which wants a private signing key to regenerate them. The kernel reads them from
# /usr/lib/firmware (merged usr: same as /lib/firmware).
# [Autark] What starts by itself: iwd (Wi-Fi), with systemd-networkd doing DHCP on any wireless link like the
# wired one; PipeWire and WirePlumber for every user session. Bluetooth stays off until wanted (systemctl enable
# --now bluetooth). sshd stays off.
step_services() {
  cat > /etc/systemd/network/20-wireless-dhcp.network << "EOF"
[Match]
Type=wlan

[Network]
DHCP=yes
IgnoreCarrierLoss=3s
EOF
  systemctl enable iwd.service
  # pipewire.service too, not only its socket: socket activation starts PipeWire on the first client, so the first
  # `wpctl status` after login saw no devices (WirePlumber still scanning). Starting it at login avoids that.
  systemctl --global enable pipewire.socket pipewire.service wireplumber.service
}

pkg_wireless_regdb() {
  install -vDm644 regulatory.db     /usr/lib/firmware/regulatory.db
  install -vDm644 regulatory.db.p7s /usr/lib/firmware/regulatory.db.p7s
}

run_pkg libtasn1             "$T_LIBTASN1"             pkg_libtasn1
run_pkg p11-kit              "$T_P11KIT"               pkg_p11_kit
run_pkg make-ca              "$T_MAKECA"               pkg_make_ca
run_pkg linux-pam            "$T_LINUXPAM"             pkg_linux_pam
run_pkg shadow-pam           "$T_SHADOW"               pkg_shadow_pam
run_pkg systemd-pam          "$T_SYSTEMD"              pkg_systemd_pam
run_pkg openssh              "$T_OPENSSH"              pkg_openssh
run_pkg sshd-unit            "$T_SYSTEMDUNITS"         pkg_sshd_unit
run_pkg libxml2              "$T_LIBXML2"              pkg_libxml2
run_pkg libpng               "$T_LIBPNG"               pkg_libpng
run_pkg freetype-pass1       "$T_FREETYPE"             pkg_freetype_pass1
run_pkg glib                 "$T_GLIB"                 pkg_glib
run_pkg harfbuzz             "$T_HARFBUZZ"             pkg_harfbuzz
run_pkg freetype-pass2       "$T_FREETYPE"             pkg_freetype_pass2
run_pkg fontconfig           "$T_FONTCONFIG"           pkg_fontconfig
run_pkg fribidi              "$T_FRIBIDI"              pkg_fribidi
run_pkg pixman               "$T_PIXMAN"               pkg_pixman
run_pkg cairo                "$T_CAIRO"                pkg_cairo
run_pkg pango                "$T_PANGO"                pkg_pango
run_pkg dejavu               "$T_DEJAVU"               pkg_dejavu
run_pkg geist                -                         step_geist
run_pkg wayland              "$T_WAYLAND"              pkg_wayland
run_pkg wayland-protocols    "$T_WAYLANDPROTOCOLS"     pkg_wayland_protocols
run_pkg libdrm               "$T_LIBDRM"               pkg_libdrm
run_pkg libevdev             "$T_LIBEVDEV"             pkg_libevdev
run_pkg mtdev                "$T_MTDEV"                pkg_mtdev
run_pkg libinput             "$T_LIBINPUT"             pkg_libinput
run_pkg xkeyboard-config     "$T_XKEYBOARDCONFIG"      pkg_xkeyboard_config
run_pkg libxkbcommon         "$T_LIBXKBCOMMON"         pkg_libxkbcommon
run_pkg hwdata               "$T_HWDATA"               pkg_hwdata
run_pkg libdisplay-info      "$T_LIBDISPLAYINFO"       pkg_libdisplay_info
run_pkg libliftoff           "$T_LIBLIFTOFF"           pkg_libliftoff
run_pkg lcms2                "$T_LCMS2"                pkg_lcms2
run_pkg seatd                "$T_SEATD"                pkg_seatd
run_pkg mako                 "$T_MAKO"                 pkg_mako
run_pkg pyyaml               "$T_PYYAML"               pkg_pyyaml
run_pkg spirv-headers        "$T_SPIRVHEADERS"         pkg_spirv_headers
run_pkg spirv-tools          "$T_SPIRVTOOLS"           pkg_spirv_tools
run_pkg glslang              "$T_GLSLANG"              pkg_glslang
run_pkg llvm                 "$T_LLVM"                 pkg_llvm
run_pkg spirv-llvm-translator "$T_SPIRVLLVMTRANSLATOR" pkg_spirv_llvm_translator
run_pkg mesa                 "$T_MESA"                 pkg_mesa
run_pkg yyjson               "$T_YYJSON"               pkg_yyjson
run_pkg glm                  "$T_GLM"                  pkg_glm
run_pkg libjpeg              "$T_LIBJPEG"              pkg_libjpeg
run_pkg wlroots              "$T_WLROOTS"              pkg_wlroots
run_pkg wayfire              "$T_WAYFIRE"              pkg_wayfire
run_pkg tllist               "$T_TLLIST"               pkg_tllist
run_pkg fcft                 "$T_FCFT"                 pkg_fcft
run_pkg foot                 "$T_FOOT"                 pkg_foot
run_pkg alsa-lib             "$T_ALSALIB"              pkg_alsa_lib
run_pkg alsa-utils           "$T_ALSAUTILS"            pkg_alsa_utils
run_pkg sbc                  "$T_SBC"                  pkg_sbc
run_pkg bluez                "$T_BLUEZ"                pkg_bluez
run_pkg lua                  "$T_LUA"                  pkg_lua
run_pkg pipewire             "$T_PIPEWIRE"             pkg_pipewire
run_pkg wireplumber          "$T_WIREPLUMBER"          pkg_wireplumber
run_pkg iwd                  "$T_IWD"                  pkg_iwd
run_pkg wireless-regdb       "$T_REGDB"                pkg_wireless_regdb
run_pkg services             -                         step_services
echo "== phase 8a (Wayland desktop) done"
