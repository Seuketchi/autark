#!/bin/bash
# The newer out-of-tree msi-ec driver (fan modes, shift mode, keyboard backlight, battery charge limit) for this laptop. The kernel's own
# msi-ec (in 7.1.8) refuses its embedded-controller firmware, "15K1IMS1.113"; upstream's lists it, for the Cyborg 15 (A13VF), with its own
# register map: charge limit at 0xd7, fan modes at 0xd4, keyboard backlight at 0x2c and 0xd3. hardware/README.md section 5 has the background.
#
#   msi-ec-module.sh build      fetch the pinned upstream source, check it against known hashes, compile it for the running kernel (any user)
#   msi-ec-module.sh check      say what the built module would drive here and what the kernel reports now (any user)
#   msi-ec-module.sh install    sign it with the kernel's module key and put it in /usr/lib/modules/<kver>/updates/ (root)
#   msi-ec-module.sh load       load it and show what it created and what the kernel said (root)
#   msi-ec-module.sh remove     unload it and delete it again, back to the kernel's own driver (root)
#
# As root on Autark:  su -c 'sh /home/tan/autark/scripts/msi-ec-module.sh build install load'
# Loading only reads from the controller (the driver's init checks one bit); nothing is written until someone sets a fan mode, a charge
# limit or a backlight. A kernel build wipes /usr/lib/modules/<kver>, so after one, run  build install  again for the new kernel.
set -euo pipefail

COMMIT=d7fbbd88e6831e56801b860e46475cbf8ddbc7c1       # BeardOverflow/msi-ec main on 2026-10-19, driver version 0.13
SHA_C=47510fad654f5f6d1302398a663c5e3725a41f099b43d09bf2762c93cc4e62cc          # msi-ec.c
SHA_MAKEFILE=4963fafaaf054fb3053b69c9f9f76cd981a9cb6efd7c8cb18bbf56c62c11dba2   # Makefile
SHA_VARS=395c3b539a9e1ea17bd9ae0229a94b90160dd3c28a3956a4e4051a54c8da2e4f       # Makefile.vars
FIRMWARE=15K1IMS1.113                                  # this laptop's embedded-controller firmware (the kernel logs it when msi_ec refuses it)
KVER=${KVER:-$(uname -r)}
WORK=${WORK:-/var/tmp/autark-msi-ec}   # not under $HOME: root installs what you built, and su -c has root's home (and an old build in it)
SRC=$WORK/src
# The key a module must carry is the one the RUNNING kernel was built with, and every kernel build makes its own, so it comes from that
# kernel's build tree; /root/kernel-keys (the older kernels' key) is only the fallback.
KEYDIR=${KEYDIR:-/usr/lib/modules/$KVER/build/certs}
[ -r "$KEYDIR/signing_key.pem" ] || KEYDIR=/root/kernel-keys
UPDATES=${UPDATES:-/usr/lib/modules/$KVER/updates}
SYSFS=/sys/devices/platform/msi-ec

die() { echo "msi-ec-module.sh: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" = 0 ] || die "$1 needs root (su -c 'sh $0 $1')"; }
sum() { sha256sum "$1" | cut -d' ' -f1; }

build() {
  [ -d "/usr/lib/modules/$KVER/build" ] || die "no kernel build tree for $KVER"
  rm -rf "$SRC"; mkdir -p "$SRC"
  curl -fsSL -m 180 "https://github.com/BeardOverflow/msi-ec/archive/$COMMIT.tar.gz" | tar -xz -C "$SRC" --strip-components=1
  [ "$(sum "$SRC/msi-ec.c")" = "$SHA_C" ] || die "msi-ec.c isn't the file this was checked against"
  [ "$(sum "$SRC/Makefile")" = "$SHA_MAKEFILE" ] || die "Makefile isn't the file this was checked against"
  [ "$(sum "$SRC/Makefile.vars")" = "$SHA_VARS" ] || die "Makefile.vars isn't the file this was checked against"
  grep -q "\"$FIRMWARE\"" "$SRC/msi-ec.c" || die "upstream's driver doesn't list firmware $FIRMWARE"
  make -C "/usr/lib/modules/$KVER/build" M="$SRC" modules -j"$(nproc)" KERNELRELEASE="$KVER" >"$WORK/build.log" 2>&1 || { tail -20 "$WORK/build.log"; die "the build failed (log: $WORK/build.log)"; }
  [ -s "$SRC/msi-ec.ko" ] || die "no module was built"
  echo "built $SRC/msi-ec.ko for $KVER: $(/usr/sbin/modinfo -F vermagic "$SRC/msi-ec.ko")"
}

check() {
  [ -s "$SRC/msi-ec.ko" ] || die "run build first"
  echo "module: version $(/usr/sbin/modinfo -F version "$SRC/msi-ec.ko"), $(/usr/sbin/modinfo -F vermagic "$SRC/msi-ec.ko")"
  # No -q: grep -q quits at the first match, strings gets SIGPIPE, and pipefail then calls a found string "not found".
  if strings "$SRC/msi-ec.ko" | grep -x "$FIRMWARE" >/dev/null; then echo "it lists firmware $FIRMWARE"; else die "the built module doesn't list $FIRMWARE"; fi
  echo "this laptop: $(cat /sys/class/dmi/id/sys_vendor) $(cat /sys/class/dmi/id/product_name)"
  echo "kernel says: $(journalctl -k --no-pager 2>/dev/null | grep -i 'msi_ec' | tail -1 || true)"
  if [ -d "$SYSFS" ]; then echo "msi-ec is loaded now: $(ls "$SYSFS" | tr '\n' ' ')"; else echo "msi-ec is not loaded now"; fi
}

install_module() {
  need_root install
  [ -s "$SRC/msi-ec.ko" ] || die "run build first (as yourself)"
  [ -r "$KEYDIR/signing_key.pem" ] && [ -r "$KEYDIR/signing_key.x509" ] || die "no module signing key in $KEYDIR (the kernel build keeps it there)"
  local sign=/usr/lib/modules/$KVER/build/scripts/sign-file
  case "$(/usr/sbin/modinfo -F vermagic "$SRC/msi-ec.ko")" in "$KVER "*) ;; *) die "the built module is for another kernel; run build again as yourself" ;; esac
  [ -x "$sign" ] || die "no $sign"
  # Sign a copy under a name modinfo recognises as a module (it won't read "msi-ec.ko.new"), check the signature there, then put it in place.
  local signed=$WORK/signed
  rm -rf "$signed"; mkdir -p "$signed"
  cp "$SRC/msi-ec.ko" "$signed/msi-ec.ko"
  "$sign" sha512 "$KEYDIR/signing_key.pem" "$KEYDIR/signing_key.x509" "$signed/msi-ec.ko"
  /usr/sbin/modinfo -F sig_id "$signed/msi-ec.ko" | grep -q . || die "the module didn't take a signature"
  install -d -m 755 "$UPDATES"
  install -m 644 "$signed/msi-ec.ko" "$UPDATES/msi-ec.ko.new"
  mv "$UPDATES/msi-ec.ko.new" "$UPDATES/msi-ec.ko"
  /usr/sbin/depmod "$KVER"
  echo "installed $UPDATES/msi-ec.ko, signed; modprobe now picks it over the kernel's own: $(/usr/sbin/modinfo -F filename msi-ec)"
}

load() {
  need_root load
  /usr/sbin/lsmod | grep -q '^msi_ec ' && /usr/sbin/rmmod msi_ec
  /usr/sbin/modprobe -v msi-ec || { journalctl -k --no-pager | tail -5; die "the module wouldn't load (is it signed with this kernel's key?)"; }
  sleep 1
  journalctl -k --no-pager | grep -i msi_ec | tail -4
  [ -d "$SYSFS" ] && echo "it created: $(ls "$SYSFS" | tr '\n' ' ')" || echo "loaded, but no $SYSFS: the driver found nothing to offer"
  echo "look at what it sees: autark-hw controls"
}

remove() {
  need_root remove
  /usr/sbin/lsmod | grep -q '^msi_ec ' && /usr/sbin/rmmod msi_ec
  rm -f "$UPDATES/msi-ec.ko"; rmdir "$UPDATES" 2>/dev/null || true
  /usr/sbin/depmod "$KVER"
  echo "removed; modprobe would now pick: $(/usr/sbin/modinfo -F filename msi-ec)"
}

[ $# -gt 0 ] || die "usage: $0 build|check|install|load|remove [more steps]"
mkdir -p "$WORK"
for step in "$@"; do
  case "$step" in
    build) build ;;
    check) check ;;
    install) install_module ;;
    load) load ;;
    remove) remove ;;
    *) die "not a step: $step" ;;
  esac
done
