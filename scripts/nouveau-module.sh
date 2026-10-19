#!/bin/bash
# The open NVIDIA driver (nouveau) for this laptop's RTX 3050 (GA107M, 10de:25a2), built as a signed module for the running kernel, without
# rebuilding the kernel. The kernel was trimmed to this laptop's modules, so CONFIG_DRM_NOUVEAU was never built; but everything nouveau
# selects (TTM, GPUVM, EXEC, the scheduler, the display helpers) is already in it, and the GSP firmware (nvidia/ga102/gsp/gsp-570.144) is
# installed. hardware/README.md section 3 and 4 have the background (there it is part of the larger "generic kernel" plan).
#
#   nouveau-module.sh build      copy nouveau's source from /sources/linux-<kver> and compile it as a module (any user; pauses itself when hot)
#   nouveau-module.sh check      what was built, and whether the firmware it asks for is installed (any user)
#   nouveau-module.sh install    sign it with the kernel's module key and put it in /usr/lib/modules/<kver>/updates/ (root)
#   nouveau-module.sh load       load it and show what the kernel said and the GPU's state (root)
#   nouveau-module.sh remove     unload it and delete it again (root)
#
# THERMALS: this laptop reset once under a big build (97 °C). The build runs at low priority with JOBS=2 and a watchdog that stops the compiler
# at STOP_AT (88 °C) and lets it go again at RESUME_AT (80 °C). It resumes where it was; run `build` again after an interruption.
set -euo pipefail

KVER=${KVER:-$(uname -r)}
SRC_TREE=${SRC_TREE:-/sources/linux-$KVER}
WORK=${WORK:-/var/tmp/autark-nouveau}   # not under $HOME: root installs from what you built, and su -c has root's home
JOBS=${JOBS:-2}
STOP_AT=${STOP_AT:-88}
RESUME_AT=${RESUME_AT:-80}
KEYDIR=${KEYDIR:-/root/kernel-keys}
UPDATES=${UPDATES:-/usr/lib/modules/$KVER/updates}
BUILD=/usr/lib/modules/$KVER/build
SRC=$WORK/nouveau

die() { echo "nouveau-module.sh: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" = 0 ] || die "$1 needs root (su -c 'sh $0 $1')"; }

hottest() {  # the hottest thermal zone, in whole °C
  local max=0 t
  for t in /sys/class/thermal/thermal_zone*/temp; do
    [ -r "$t" ] || continue
    t=$(( $(cat "$t") / 1000 ))
    [ "$t" -gt "$max" ] && max=$t
  done
  echo "$max"
}

build() {
  [ -d "$BUILD" ] || die "no kernel build tree for $KVER"
  [ -d "$SRC_TREE/drivers/gpu/drm/nouveau" ] || die "no nouveau source in $SRC_TREE"
  [ "$(make -s -C "$BUILD" kernelrelease 2>/dev/null)" = "$KVER" ] || die "the build tree at $BUILD isn't $KVER"
  mkdir -p "$WORK"
  # Copied once; a second run carries on with what was compiled.
  if [ ! -d "$SRC" ]; then cp -r "$SRC_TREE/drivers/gpu/drm/nouveau" "$SRC"; fi
  # nouveau's Kconfig selects MXM_WMI (swappable-GPU laptops' firmware calls), which this kernel doesn't have, so the link wants three functions
  # nobody provides. This GPU is soldered, so the honest answer to each is "not here": a stub that says so (mxm_wmi_supported() is false, which
  # the one caller checks before using the other two).
  cat > "$SRC/autark_mxm_stub.c" <<'STUB'
// SPDX-License-Identifier: GPL-2.0-or-later
/* Stand-in for the kernel's MXM WMI driver (CONFIG_MXM_WMI), which this kernel doesn't build: no MXM-socketed GPU, so no MXM calls. */
#include <linux/types.h>
#include <linux/errno.h>
#include <linux/mxm-wmi.h>

bool mxm_wmi_supported(void) { return false; }
int mxm_wmi_call_mxds(int adapter) { return -ENODEV; }
int mxm_wmi_call_mxmx(int adapter) { return -ENODEV; }
STUB
  grep -q autark_mxm_stub "$SRC/Kbuild" || echo 'nouveau-y += autark_mxm_stub.o' >> "$SRC/Kbuild"
  # nouveau's Kconfig sub-options (defaults), as the build needs them: make variables for the Kbuild, defines for the C.
  setsid nice -n 10 make -C "$BUILD" M="$SRC" -j"$JOBS" KERNELRELEASE="$KVER" \
      CONFIG_DRM_NOUVEAU=m CONFIG_NOUVEAU_DEBUG=5 CONFIG_NOUVEAU_DEBUG_DEFAULT=3 CONFIG_DRM_NOUVEAU_BACKLIGHT=y \
      'KCFLAGS=-DCONFIG_NOUVEAU_DEBUG=5 -DCONFIG_NOUVEAU_DEBUG_DEFAULT=3 -DCONFIG_DRM_NOUVEAU_BACKLIGHT=1' \
      modules >>"$WORK/build.log" 2>&1 &
  local pid=$! stopped=0 temp
  echo "compiling nouveau ($JOBS jobs, low priority); pauses at ${STOP_AT} °C, resumes at ${RESUME_AT} °C"
  while kill -0 "$pid" 2>/dev/null; do
    temp=$(hottest)
    if [ "$stopped" = 0 ] && [ "$temp" -ge "$STOP_AT" ]; then
      kill -STOP -- "-$pid" 2>/dev/null || true; stopped=1; echo "$(date +%T) ${temp} °C: paused the build"
    elif [ "$stopped" = 1 ] && [ "$temp" -le "$RESUME_AT" ]; then
      kill -CONT -- "-$pid" 2>/dev/null || true; stopped=0; echo "$(date +%T) ${temp} °C: carrying on"
    fi
    sleep 2
  done
  wait "$pid" || { grep -E "error|Error" "$WORK/build.log" | head -8; die "the build failed (log: $WORK/build.log)"; }
  [ -s "$SRC/nouveau.ko" ] || die "no module was built"
  echo "built $SRC/nouveau.ko ($(du -h "$SRC/nouveau.ko" | cut -f1)): $(/usr/sbin/modinfo -F vermagic "$SRC/nouveau.ko")"
}

check() {
  [ -s "$SRC/nouveau.ko" ] || die "run build first"
  local vm; vm=$(/usr/sbin/modinfo -F vermagic "$SRC/nouveau.ko")
  echo "vermagic: $vm"
  case "$vm" in "$KVER "*) ;; *) die "built for a different kernel" ;; esac
  echo "depends:  $(/usr/sbin/modinfo -F depends "$SRC/nouveau.ko")"
  echo "firmware the module can ask for on this GPU's family (GA10x):"
  local f missing=0
  for f in $(/usr/sbin/modinfo -F firmware "$SRC/nouveau.ko" | grep -E "nvidia/ga10[27]/gsp/"); do
    if [ -e "/usr/lib/firmware/$f.zst" ] || [ -e "/usr/lib/firmware/$f" ]; then echo "  have  $f"; else echo "  MISSING  $f"; missing=1; fi
  done
  [ "$missing" = 0 ] || echo "(a missing file here only matters if it is the one this GPU loads)"
  echo "the GPU now: $(cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status 2>/dev/null) ($(cat /sys/bus/pci/devices/0000:01:00.0/vendor 2>/dev/null) $(cat /sys/bus/pci/devices/0000:01:00.0/device 2>/dev/null)), driver: $(basename "$(readlink /sys/bus/pci/devices/0000:01:00.0/driver 2>/dev/null)" 2>/dev/null)"
}

install_module() {
  need_root install
  [ -s "$SRC/nouveau.ko" ] || die "run build first (as yourself)"
  [ -r "$KEYDIR/signing_key.pem" ] && [ -r "$KEYDIR/signing_key.x509" ] || die "no module signing key in $KEYDIR"
  local sign=$BUILD/scripts/sign-file signed=$WORK/signed
  [ -x "$sign" ] || die "no $sign"
  rm -rf "$signed"; mkdir -p "$signed"
  cp "$SRC/nouveau.ko" "$signed/nouveau.ko"
  "$sign" sha512 "$KEYDIR/signing_key.pem" "$KEYDIR/signing_key.x509" "$signed/nouveau.ko"
  /usr/sbin/modinfo -F sig_id "$signed/nouveau.ko" | grep -q . || die "the module didn't take a signature"
  install -d -m 755 "$UPDATES"
  install -m 644 "$signed/nouveau.ko" "$UPDATES/nouveau.ko.new"
  mv "$UPDATES/nouveau.ko.new" "$UPDATES/nouveau.ko"
  /usr/sbin/depmod "$KVER"
  echo "installed $UPDATES/nouveau.ko, signed. It will load on its own at the next boot for the GPU; or now: $0 load"
}

load() {
  need_root load
  local gpu=/sys/bus/pci/devices/0000:01:00.0
  /usr/sbin/modprobe -v nouveau || { journalctl -k --no-pager | tail -8; die "nouveau wouldn't load"; }
  sleep 6
  journalctl -k --no-pager | grep -i -E "nouveau|nvkm" | tail -12
  echo "the GPU: driver $(basename "$(readlink $gpu/driver 2>/dev/null)" 2>/dev/null), power $(cat $gpu/power/runtime_status 2>/dev/null)"
  echo "next: autark-hw doctor    (and if anything is wrong:  $0 remove)"
}

remove() {
  need_root remove
  /usr/sbin/modprobe -r nouveau 2>/dev/null || /usr/sbin/rmmod nouveau 2>/dev/null || true
  rm -f "$UPDATES/nouveau.ko"; rmdir "$UPDATES" 2>/dev/null || true
  /usr/sbin/depmod "$KVER"
  echo "removed. modprobe would now find: $(/usr/sbin/modinfo -F filename nouveau 2>&1 | head -1)"
}

[ $# -gt 0 ] || die "usage: $0 build|check|install|load|remove [more steps]"
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
