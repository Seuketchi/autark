#!/bin/sh
# viber: start Viber on Wayland. Viber is Viber's own build (Qt6 and a Chromium engine bundled in it), copied from Ubuntu
# to /opt/viber by viber-install.sh; the libraries it needs outside that folder are packages (libglvnd, nss, libpulse, ...).
#
#   viber                    start it; a viber:// link can be passed as the argument
#   VIBER_NO_SANDBOX=1 viber  without the Chromium sandbox, if it won't start with it
#
# Its data (chats, the phone link) is in ~/.ViberPC.

set -eu

[ -x /opt/viber/Viber ] || { echo "viber: /opt/viber/Viber isn't installed; run viber-install.sh" >&2; exit 1; }

# Viber picks the X11 plugin by default, and there is no X server here.
export QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-wayland}
# Its bundled libxml2 wants ICU 74, which sits in its own lib folder, but libxml2 has no runpath to find it there.
export LD_LIBRARY_PATH=/opt/viber/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
if [ -n "${VIBER_NO_SANDBOX:-}" ]; then
  export QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox ${QTWEBENGINE_CHROMIUM_FLAGS:-}"
fi

cd /opt/viber
exec /opt/viber/Viber "$@"
