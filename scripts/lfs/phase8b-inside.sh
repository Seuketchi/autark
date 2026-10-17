#!/bin/bash
# Phase 8b: the shell toolchain. Runs INSIDE the chroot as root, started by scripts/stage-8b.sh (or ch7-chroot.sh
# with INSIDE=phase8b-inside.sh). Builds Rust, GTK4 and its icons, polkit, UPower, gtk4-layer-shell, sudo-rs, the
# oo7 keyring with its PAM module, and last the shell itself (autark-tools). The package list, versions and
# per-package decisions are in docs/specs/phase-8b-packages.md; this script is that spec as commands.
#
# Run (from the host):
#   sudo LFS=/mnt/lfs INSIDE=phase8b-inside.sh bash scripts/lfs/ch7-chroot.sh [pkg...]
# With no names it builds everything in order and skips what has a /sources/.done/8b-<name> marker; with names
# (the first column of the run_pkg lines at the bottom, e.g. `gtk4 autark-tools`) it builds only those.
# Tarballs are expected in /sources (staged from sources-8b/ by scripts/fetch-8b.sh and stage-8b.sh), with the Rust
# crates the chroot can't download in /sources/crates-8b.tar.
#
# Commands follow BLFS 13.1-systemd except where marked [Autark]. Deviations from BLFS, all of them:
#  - Rust: prefix /usr (not /opt/rustc-1.97.1, decisions.md "Phase 8b"), built on 8a's LLVM 22.1.8, the three stage0
#    files taken from /sources (no network), no test suite, no LIBSSH2_SYS_USE_PKG_CONFIG (libssh2 isn't installed).
#  - cargo-c and librsvg are not built (GTK and Adwaita don't need librsvg; decisions.md "Phase 8b").
#  - tiff is added (GTK 4.22 requires it; BLFS's GTK page doesn't list it); docs, tests and contrib off.
#  - gdk-pixbuf keeps its own png/jpeg/gif/tiff loaders instead of BLFS's glycin; no introspection, man or tests.
#  - GTK: Wayland only (x11 and broadway off), no Vulkan, GStreamer, CUPS, introspection, docs, demos or tests.
#  - libepoxy, graphene, libgudev, UPower, gtk4-layer-shell: introspection, vapi, docs and tests off (all pinned).
#  - polkit: os_type=lfs and pam_prefix=/etc/pam.d (so its PAM file uses 8a's four system-* files), no man, tests
#    or introspection.
#  - UPower: polkit pinned on, libimobiledevice off, no libusb (UPower 1.91 doesn't use it).
#  - gtk4-layer-shell, sudo-rs and oo7 are upstream (not in BLFS); sudo-rs and oo7 from their crates.io .crate files.
#  - sudo-rs installs sudo, visudo and sudoedit only (Shadow's su stays); /etc/pam.d/sudo pulls in Settings'
#    /etc/pam.d/autark-fingerprint before the password (decisions.md "Fingerprint & Lock v1").
#  - oo7-pam: `auth optional` and `session optional` in /etc/pam.d/login only, so the login password unlocks the
#    keyring at a console login; oo7-daemon.service enabled for every user so its socket is there when the session
#    opens.
#  - Rust programs (sudo-rs, oo7, autark-tools) build with RUSTFLAGS="-C target-cpu=x86-64-v3", like CFLAGS.
set -euo pipefail

if [ ! -e /sources/wget-list-systemd ] || grep -qi ubuntu /etc/os-release 2>/dev/null; then
  echo "phase8b-inside.sh: not inside the Autark chroot; refusing to run" >&2
  exit 1
fi

logs=/sources/logs
mkdir -p "$logs" /sources/.done /sources/.track /var/lib/autark/files
srcdir=/sources
source "$(dirname "$0")/build-lib.sh"

export CFLAGS="-O2 -march=x86-64-v3 -pipe -fstack-protector-strong -fstack-clash-protection -fcf-protection=full -D_FORTIFY_SOURCE=3"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-Wl,-O1 -Wl,-z,relro -Wl,-z,now"

# Tarball names, in one place (they match scripts/sources-8b.txt).
T_RUST=rustc-1.97.1-src.tar.xz
T_TIFF=tiff-4.7.2.tar.gz
T_SHAREDMIMEINFO=shared-mime-info-2.5.1.tar.gz
T_GDKPIXBUF=gdk-pixbuf-2.44.7.tar.xz
T_GRAPHENE=graphene-1.10.8.tar.xz
T_LIBEPOXY=libepoxy-1.5.10.tar.xz
T_ISOCODES=iso-codes-v4.20.1.tar.gz
T_HICOLOR=hicolor-icon-theme-0.18.tar.xz
T_GTK4=gtk-4.22.4.tar.xz
T_ADWAITA=adwaita-icon-theme-50.0.tar.xz
T_LAYERSHELL=gtk4-layer-shell-1.3.0.tar.gz
T_DUKTAPE=duktape-2.7.0.tar.xz
T_POLKIT=polkit-127.tar.gz
T_LIBGUDEV=libgudev-238.tar.xz
T_UPOWER=upower-v1.91.3.tar.bz2
T_SUDORS=sudo-rs-0.2.15.tar.gz
T_OO7DAEMON=oo7-daemon-0.6.0.tar.gz
T_OO7PAM=oo7-pam-0.6.0.tar.gz
T_AUTARKTOOLS=autark-tools.tar.gz
# Rust's stage0 compiler, from the release's src/stage0 (compiler_date 2026-05-28).
STAGE0_DATE=2026-05-28
STAGE0="rustc-1.96.0-x86_64-unknown-linux-gnu.tar.xz rust-std-1.96.0-x86_64-unknown-linux-gnu.tar.xz cargo-1.96.0-x86_64-unknown-linux-gnu.tar.xz"

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
  if [ -e "/sources/.done/8b-$name" ]; then echo "== $name: already done, skipped"; return; fi
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
  touch "/sources/.done/8b-$name"
}

# [Autark] Cargo reads crates only from /sources/crates-8b (fetch-8b.sh vendored them against each Cargo.lock; cargo
# checks every file's sha256 again as it builds) and never touches the network. Call inside a pkg_ function.
offline_cargo() {
  [ -d /sources/crates-8b ] || tar -xf /sources/crates-8b.tar -C /sources
  export CARGO_HOME=$PWD/.cargo-home CARGO_NET_OFFLINE=true RUSTFLAGS="-C target-cpu=x86-64-v3"
  mkdir -p "$CARGO_HOME"
  cat > "$CARGO_HOME/config.toml" << "EOF"
[source.crates-io]
replace-with = "vendored"

[source.vendored]
directory = "/sources/crates-8b"
EOF
}

# ---- Rust ----

# [Autark] prefix /usr, description, no i686 section; stage0 staged into build/cache; no tests (+15 SBU).
pkg_rust() {
  cat > bootstrap.toml << "EOF"
change-id = 154587

[llvm]
link-shared = true
targets = "X86"

[build]
description = "for Autark"
docs = false
tools = ["cargo", "clippy", "rustdoc", "rustfmt", "src"]

[install]
prefix = "/usr"
docdir = "share/doc/rustc-1.97.1"

[rust]
channel = "stable"
lto = "thin"
codegen-units = 1
llvm-bitcode-linker = false

[target.x86_64-unknown-linux-gnu]
llvm-config = "/usr/bin/llvm-config"
EOF
  # Bootstrap looks here before downloading and checks each file against src/stage0's sha256.
  mkdir -p "build/cache/$STAGE0_DATE"
  for f in $STAGE0; do cp -v "/sources/$f" "build/cache/$STAGE0_DATE/"; done
  export LIBSQLITE3_SYS_USE_PKG_CONFIG=1
  ./x.py build
  ./x.py install
  rm -fv /usr/share/doc/rustc-1.97.1/*.old
  install -vm644 README.md /usr/share/doc/rustc-1.97.1
  if [ -e /etc/bash_completion.d/cargo ]; then
    install -vdm755 /usr/share/bash-completion/completions
    mv -v /etc/bash_completion.d/cargo /usr/share/bash-completion/completions
  fi
  ldconfig
  rustc --version
  cargo --version
}

# ---- GTK4 and what it needs ----

# [Autark] docs, tests and contrib off (docs would need Sphinx), so no doc folder to rename.
pkg_tiff() {
  mkdir -p tiff-build
  cd       tiff-build
  cmake -D CMAKE_INSTALL_PREFIX=/usr \
        -D CMAKE_BUILD_TYPE=Release  \
        -D tiff-docs=OFF             \
        -D tiff-tests=OFF            \
        -D tiff-contrib=OFF          \
        -W no-author -G Ninja ..
  ninja
  ninja install
}

pkg_shared_mime_info() {
  mkdir build
  cd    build
  meson setup --prefix=/usr         \
              --buildtype=release   \
              -D update-mimedb=true \
              -D build-tests=false  \
              -D build-spec=false   \
              ..
  ninja
  ninja install
}

# [Autark] Its own loaders (png and jpeg built in, gif and tiff as modules) instead of glycin; others off.
pkg_gdk_pixbuf() {
  mkdir build
  cd    build
  meson setup ..                   \
        --prefix=/usr              \
        --buildtype=release        \
        --wrap-mode=nofallback     \
        -D png=enabled             \
        -D jpeg=enabled            \
        -D gif=enabled             \
        -D tiff=enabled            \
        -D glycin=disabled         \
        -D others=disabled         \
        -D thumbnailer=disabled    \
        -D introspection=disabled  \
        -D man=false               \
        -D tests=false             \
        -D installed_tests=false
  ninja
  ninja install
  gdk-pixbuf-query-loaders --update-cache
}

pkg_graphene() {
  mkdir build
  cd    build
  meson setup --prefix=/usr             \
              --buildtype=release       \
              -D introspection=disabled \
              -D tests=false            \
              -D installed_tests=false  \
              -D gtk_doc=false          \
              ..
  ninja
  ninja install
}

# [Autark] EGL only: no GLX, no X11.
pkg_libepoxy() {
  mkdir build
  cd    build
  meson setup --prefix=/usr       \
              --buildtype=release \
              -D egl=yes          \
              -D glx=no           \
              -D x11=false        \
              -D tests=false      \
              -D docs=false       \
              ..
  ninja
  ninja install
}

pkg_iso_codes() {
  mkdir build
  cd    build
  meson setup --prefix=/usr ..
  ninja
  ninja install
}

pkg_hicolor() {
  mkdir build
  cd    build
  meson setup --prefix=/usr --buildtype=release ..
  ninja
  ninja install
}

# [Autark] See the header: Wayland only; every switch is checked against GTK's meson.options in the spec.
pkg_gtk4() {
  mkdir build
  cd    build
  meson setup --prefix=/usr                \
              --buildtype=release          \
              --wrap-mode=nofallback       \
              -D x11-backend=false         \
              -D wayland-backend=true      \
              -D broadway-backend=false    \
              -D media-gstreamer=disabled  \
              -D print-cups=disabled       \
              -D print-cpdb=disabled       \
              -D vulkan=disabled           \
              -D introspection=disabled    \
              -D documentation=false       \
              -D man-pages=false           \
              -D build-demos=false         \
              -D build-testsuite=false     \
              -D build-examples=false      \
              -D build-tests=false         \
              ..
  ninja
  ninja install
  glib-compile-schemas /usr/share/glib-2.0/schemas
}

pkg_adwaita() {
  mkdir build
  cd    build
  meson setup --prefix=/usr ..
  ninja
  rm -rf /usr/share/icons/Adwaita/
  ninja install
  gtk4-update-icon-cache -qtf /usr/share/icons/Adwaita
  gtk4-update-icon-cache -qtf /usr/share/icons/hicolor
}

# [Autark] Upstream (not in BLFS). One library for both the layer-shell and the session-lock crates.
pkg_gtk4_layer_shell() {
  meson setup build --prefix=/usr      \
                    --buildtype=release \
                    -D introspection=false \
                    -D vapi=false       \
                    -D examples=false   \
                    -D docs=false       \
                    -D tests=false      \
                    -D smoke-tests=false
  ninja -C build
  ninja -C build install
}

# ---- polkit and UPower ----

pkg_duktape() {
  sed -i 's/-Os/-O2/' Makefile.sharedlibrary
  make -f Makefile.sharedlibrary INSTALL_PREFIX=/usr
  make -f Makefile.sharedlibrary INSTALL_PREFIX=/usr install
}

# [Autark] os_type=lfs and pam_prefix=/etc/pam.d (see the header); no man pages (need libxslt and DocBook), no
# tests (need dbusmock), no introspection.
pkg_polkit() {
  # The user first, or install can't hand /etc/polkit-1/rules.d to it.
  groupadd -fg 27 polkitd
  getent passwd polkitd > /dev/null ||
    useradd -c "PolicyKit Daemon Owner" -d /etc/polkit-1 -u 27 -g polkitd -s /bin/false polkitd
  mkdir build
  cd    build
  meson setup ..                   \
        --prefix=/usr              \
        --buildtype=release        \
        -D session_tracking=logind \
        -D os_type=lfs             \
        -D pam_prefix=/etc/pam.d   \
        -D authfw=pam              \
        -D introspection=false     \
        -D man=false               \
        -D tests=false
  ninja
  ninja install
  grep -q system-account /etc/pam.d/polkit-1   # the os_type=lfs file, not the all-system-auth fallback
}

pkg_libgudev() {
  mkdir build
  cd    build
  meson setup --prefix=/usr             \
              --buildtype=release       \
              -D introspection=disabled \
              -D vapi=disabled          \
              -D tests=disabled         \
              -D gtk_doc=false          \
              ..
  ninja
  ninja install
}

pkg_upower() {
  mkdir build
  cd    build
  meson setup ..                   \
        --prefix=/usr              \
        --buildtype=release        \
        -D gtk-doc=false           \
        -D man=false               \
        -D introspection=disabled  \
        -D idevice=disabled        \
        -D polkit=enabled          \
        -D installed_tests=false
  ninja
  ninja install
  systemd-hwdb update
}

# ---- sudo-rs and the keyring (upstream, from crates.io) ----

pkg_sudo_rs() {
  offline_cargo
  cargo build --release --locked --offline
  install -v -m4755 -o root -g root target/release/sudo /usr/bin/sudo
  install -v -m755 target/release/visudo /usr/bin/visudo
  ln -sfv sudo /usr/bin/sudoedit
  install -v -Dm644 docs/man/sudo.8.man    /usr/share/man/man8/sudo.8
  install -v -Dm644 docs/man/visudo.8.man  /usr/share/man/man8/visudo.8
  install -v -Dm644 docs/man/sudoers.5.man /usr/share/man/man5/sudoers.5
  # Settings' fingerprint switch rewrites this one file (autark-fingerprint-sudo); until then, password only.
  [ -e /etc/pam.d/autark-fingerprint ] ||
    echo "# Written by Settings (autark-fingerprint-sudo): sudo asks for the password only." > /etc/pam.d/autark-fingerprint
  cat > /etc/pam.d/sudo << "EOF"
# Begin /etc/pam.d/sudo

# A fingerprint first when Settings turned it on, then the password.
auth      include     autark-fingerprint
auth      include     system-auth
account   include     system-account
session   required    pam_env.so
session   include     system-session

# End /etc/pam.d/sudo
EOF
  chmod 644 /etc/pam.d/sudo
  if [ ! -e /etc/sudoers ]; then
    install -v -dm750 /etc/sudoers.d
    cat > /etc/sudoers << "EOF"
Defaults secure_path="/usr/sbin:/usr/bin"
%wheel ALL=(ALL:ALL) ALL
@includedir /etc/sudoers.d
EOF
    chmod 440 /etc/sudoers
  fi
  visudo -c
}

# The build folder must sit inside the source tree: its meson runs cargo from there.
pkg_oo7_daemon() {
  offline_cargo
  meson setup build --prefix=/usr --buildtype=release -D systemd=enabled
  ninja -C build
  ninja -C build install
}

pkg_oo7_pam() {
  offline_cargo
  meson setup build --prefix=/usr --buildtype=release -D pam_moduledir=/usr/lib/security
  ninja -C build
  ninja -C build install
}

# ---- The shell ----

# [Autark] The workspace at the commit in sources-8b/autark-tools.commit. Binaries to /usr/bin, the two root helpers
# to /usr/libexec (where the code and units look), autark-init not installed (initramfs, deferred).
pkg_autark_tools() {
  offline_cargo
  cargo build --release --locked --offline --workspace
  { cargo test --release --locked --offline --workspace; } || testfail autark-tools
  for bin in target/release/autark-*; do
    [ -f "$bin" ] && [ -x "$bin" ] || continue
    case "${bin##*/}" in
      autark-init) ;;
      autark-stats-power) install -v -Dm755 "$bin" /usr/libexec/autark-stats-power ;;
      autark-fingerprint-sudo) install -v -Dm755 "$bin" /usr/libexec/autark/autark-fingerprint-sudo ;;
      *) install -v -m755 "$bin" /usr/bin/ ;;
    esac
  done
  # The RAPL helper: systemd unit, D-Bus activation and policy (crates/autark-stats/data).
  install -v -Dm644 crates/autark-stats/data/autark-stats-power.service   /usr/lib/systemd/system/autark-stats-power.service
  install -v -Dm644 crates/autark-stats/data/org.autark.StatsPower1.service /usr/share/dbus-1/system-services/org.autark.StatsPower1.service
  install -v -Dm644 crates/autark-stats/data/org.autark.StatsPower1.conf  /usr/share/dbus-1/system.d/org.autark.StatsPower1.conf
  # autark-lock refuses to lock without its PAM file.
  cat > /etc/pam.d/autark-lock << "EOF"
# Begin /etc/pam.d/autark-lock
auth      include     system-auth
account   include     system-account
# End /etc/pam.d/autark-lock
EOF
  # The launcher lists apps from desktop entries; these are the shell's own windows.
  install -v -dm755 /usr/share/applications
  local id name exec
  while IFS='|' read -r id name exec; do
    cat > "/usr/share/applications/$id.desktop" << EOF
[Desktop Entry]
Type=Application
Name=$name
Exec=$exec
Icon=$id
Terminal=false
EOF
  done << "EOF"
autark-files|Files|autark-files %U
autark-notes|Notes|autark-notes
autark-settings|Settings|autark-settings
autark-monitor|Activity|autark-monitor
EOF
  # gtk4-layer-shell must load before libwayland-client (its linking.md), or layer surfaces break.
  local order
  order=$(readelf -d /usr/bin/autark-bar | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | grep -n -E 'gtk4-layer-shell|wayland-client' || true)
  echo "autark-bar NEEDED order: $order"
  case "$order" in
    *wayland-client*gtk4-layer-shell*) testfail "autark-tools: libwayland-client is linked before libgtk4-layer-shell" ;;
  esac
}

# ---- Caches and services ----

step_services() {
  update-mime-database /usr/share/mime
  gdk-pixbuf-query-loaders --update-cache
  glib-compile-schemas /usr/share/glib-2.0/schemas
  # The keyring starts with each user's session, so pam_oo7's socket is there when login opens it.
  systemctl --global enable oo7-daemon.service
  # The login password unlocks the keyring: stashed at auth, handed to the daemon when the session opens.
  if ! grep -q pam_oo7 /etc/pam.d/login; then
    sed -i '/^# End \/etc\/pam.d\/login/i # The keyring (oo7): the login password unlocks it.\nauth      optional    pam_oo7.so\nsession   optional    pam_oo7.so' /etc/pam.d/login
    grep -q pam_oo7 /etc/pam.d/login || testfail "pam_oo7 not added to /etc/pam.d/login (no End marker)"
  fi
}

run_pkg rust               "$T_RUST"            pkg_rust
run_pkg tiff               "$T_TIFF"            pkg_tiff
run_pkg shared-mime-info   "$T_SHAREDMIMEINFO"  pkg_shared_mime_info
run_pkg gdk-pixbuf         "$T_GDKPIXBUF"       pkg_gdk_pixbuf
run_pkg graphene           "$T_GRAPHENE"        pkg_graphene
run_pkg libepoxy           "$T_LIBEPOXY"        pkg_libepoxy
run_pkg iso-codes          "$T_ISOCODES"        pkg_iso_codes
run_pkg hicolor            "$T_HICOLOR"         pkg_hicolor
run_pkg gtk4               "$T_GTK4"            pkg_gtk4
run_pkg adwaita            "$T_ADWAITA"         pkg_adwaita
run_pkg gtk4-layer-shell   "$T_LAYERSHELL"      pkg_gtk4_layer_shell
run_pkg duktape            "$T_DUKTAPE"         pkg_duktape
run_pkg polkit             "$T_POLKIT"          pkg_polkit
run_pkg libgudev           "$T_LIBGUDEV"        pkg_libgudev
run_pkg upower             "$T_UPOWER"          pkg_upower
run_pkg sudo-rs            "$T_SUDORS"          pkg_sudo_rs
run_pkg oo7-daemon         "$T_OO7DAEMON"       pkg_oo7_daemon
run_pkg oo7-pam            "$T_OO7PAM"          pkg_oo7_pam
run_pkg autark-tools       "$T_AUTARKTOOLS"     pkg_autark_tools
run_pkg services           -                    step_services
echo "== phase 8b (shell toolchain) done: $(rustc --version), GTK $(pkg-config --modversion gtk4), $(sudo --version | head -1)"
