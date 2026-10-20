#!/bin/sh
# viber-install.sh: make Viber runnable. Run as root, from a checkout that has the Viber recipes:
#
#   sudo scripts/viber-install.sh
#
# 1. puts the recipes it needs into /usr/src/autark/scripts/pkg (root-owned on purpose; only these files are copied),
# 2. builds and installs the 15 small libraries; Mesa and the rest of the desktop are not touched yet,
# 3. installs libglvnd and builds and installs the new Mesa. libglvnd takes libEGL.so.1, libGLESv1_CM, libGLESv2 and their
#    headers over from the old mesa (hence --force), so from that moment until Mesa is installed, about as long as the Mesa
#    build, a program started fresh can't open EGL. Don't start new programs meanwhile; running ones keep their libraries.
#    Afterwards log out and back in, so the compositor and everything else use the new ones.
#    If the Mesa build fails, run this script again; `autark-pkg rollback mesa` goes back to the previous Mesa later.
# 4. copies Viber from the read-only Ubuntu disk (/mnt/ubuntu-ro, mounted by hand) to /opt/viber,
# 5. adds the viber command, its menu entry and its icon.

set -eu

[ "$(id -u)" = 0 ] || { echo "viber-install.sh: run it with sudo" >&2; exit 1; }

here=$(cd "$(dirname "$0")" && pwd)
recipes=$here/pkg
ubuntu=${UBUNTU_RO:-/mnt/ubuntu-ro}
dest=/usr/src/autark/scripts/pkg

libs="libXScrnSaver libXtst libxkbfile libxshmfence nspr nss snappy openjpeg libsndfile libpulse libvdpau libva
      openssl3-libs krb5 libssh"
packages="$libs libglvnd mesa"

[ -d "$dest" ] || { echo "viber-install.sh: $dest doesn't exist" >&2; exit 1; }
for p in $packages; do
  [ -f "$recipes/$p.sh" ] || { echo "viber-install.sh: no recipe $recipes/$p.sh" >&2; exit 1; }
done
[ -f "$ubuntu/opt/viber/Viber" ] || [ -x /opt/viber/Viber ] || {
  echo "viber-install.sh: Viber isn't at $ubuntu/opt/viber; mount the Ubuntu disk read-only first" >&2; exit 1; }

echo "== recipes"
for p in $packages; do install -m644 -o root -g root "$recipes/$p.sh" "$dest/$p.sh"; done

echo "== libraries"
autark-pkg install $libs

echo "== libglvnd and Mesa (don't start new programs until this finishes)"
autark-pkg --force install libglvnd mesa

echo "== Viber"
if [ ! -x /opt/viber/Viber ]; then
  cp -a "$ubuntu/opt/viber" /opt/viber
  chown -R root:root /opt/viber
fi
install -m755 "$here/viber.sh" /usr/bin/viber
# A PNG: the dock's GTK has no SVG loader here.
install -Dm644 "$ubuntu/usr/share/pixmaps/viber.png" /usr/share/icons/hicolor/256x256/apps/viber.png
# GTK trusts icon-theme.cache over the folders while it is newer than them, so a new icon needs the cache rebuilt.
gtk4-update-icon-cache -f -t /usr/share/icons/hicolor
cat > /usr/share/applications/viber.desktop << 'EOF'
[Desktop Entry]
Name=Viber
Comment=Viber VoIP and messenger
Exec=viber %u
Icon=viber
Terminal=false
Type=Application
Categories=Network;InstantMessaging;P2P;
MimeType=x-scheme-handler/viber;
EOF

echo "Done. Log out and back in, then run: viber"
