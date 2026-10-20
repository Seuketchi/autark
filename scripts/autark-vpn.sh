#!/bin/sh
# autark-vpn: connect to an OpenVPN profile in ~/.config/openvpn/<name>/<name>.ovpn.
#
#   autark-vpn            list the profiles and which are connected
#   autark-vpn <name>     connect; stays in this terminal (asks for username, password and any 2FA code), Ctrl-C disconnects
#   autark-vpn down <name>  disconnect one from another terminal
#
# openvpn runs as root through sudo, so it asks for your password first. The tunnel is called vpn-<name>, and its DNS goes
# to systemd-resolved through the dns-updown script that comes with openvpn. Nothing is saved: credentials are typed each time.

set -eu

PROFILES=${AUTARK_VPN_DIR:-$HOME/.config/openvpn}
RUN=${AUTARK_VPN_RUN:-/run}
# In /usr/sbin, which isn't on a user's PATH here.
OPENVPN=${AUTARK_VPN_OPENVPN:-/usr/sbin/openvpn}

die() { echo "autark-vpn: $*" >&2; exit 1; }

# A profile's name is its folder's, kept to what a tunnel name and a file name can hold.
valid() {
  case $1 in
    '' | *[!a-z0-9_-]*) die "'$1' isn't a profile name (lowercase letters, digits, - and _)" ;;
  esac
  [ ${#1} -le 10 ] || die "'$1' is too long: the tunnel is named vpn-$1, and Linux limits a name to 15 characters"
}

pidfile() { echo "$RUN/autark-vpn-$1.pid"; }

connected() {
  [ -r "$(pidfile "$1")" ] && kill -0 "$(cat "$(pidfile "$1")")" 2>/dev/null
}

list() {
  found=0
  for file in "$PROFILES"/*/*.ovpn; do
    [ -e "$file" ] || continue
    name=$(basename "$(dirname "$file")")
    case $name in *[!a-z0-9_-]*) continue ;; esac
    found=1
    if connected "$name"; then echo "$name  connected"; else echo "$name"; fi
  done
  [ "$found" = 1 ] || echo "no profiles in $PROFILES (one folder each, with <name>.ovpn inside)"
}

down() {
  valid "$1"
  connected "$1" || die "$1 isn't connected"
  sudo kill -TERM "$(cat "$(pidfile "$1")")"
  echo "disconnecting $1"
}

up() {
  valid "$1"
  config=$PROFILES/$1/$1.ovpn
  [ -f "$config" ] || die "no profile $config"
  [ -x "$OPENVPN" ] || die "openvpn isn't installed: sudo autark-pkg install openvpn"
  ! connected "$1" || die "$1 is already connected: autark-vpn down $1"
  echo "connecting $1 (Ctrl-C to disconnect)"
  # Later options win over the profile's own, so the tunnel's name applies whatever the profile says. --script-security 2
  # lets openvpn's own dns-updown run (no --up script, so it does).
  # --cd makes a profile's relative file names work.
  exec sudo "$OPENVPN" --config "$config" --cd "$PROFILES/$1" \
    --dev "vpn-$1" --dev-type tun \
    --script-security 2 \
    --writepid "$(pidfile "$1")"
}

case ${1:-} in
  '' | list | -l | --list) list ;;
  -h | --help | help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//' ;;
  down) [ $# -eq 2 ] || die "usage: autark-vpn down <name>"; down "$2" ;;
  *) [ $# -eq 1 ] || die "usage: autark-vpn <name>"; up "$1" ;;
esac
