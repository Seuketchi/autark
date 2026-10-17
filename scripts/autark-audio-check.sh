#!/bin/bash
# Autark audio check: run ON Autark, as root, from a text console or foot:   bash /boot/efi/audio-check.sh
# Unmutes the internal sound card's playback controls, plays test sounds and asks whether you heard them, and writes
# everything to /boot/efi/audio-report.txt (Autark's EFI partition, which Ubuntu can read without your passphrase).
# Safe to run again; it only changes mixer levels (saved with alsactl store once something is heard).
set -u
REPORT=/boot/efi/audio-report.txt
USER_NAME=tan
USER_UID=$(id -u $USER_NAME 2>/dev/null || echo 1000)
exec > >(tee "$REPORT") 2>&1
section() { echo; echo "=================== $*"; }

section "when, kernel"
date; uname -r

section "cards"
cat /proc/asound/cards
CARD=$(awk '/sof|hda-dsp|HDA-Intel PCH/ && $1 ~ /^[0-9]+$/ {print $1; exit}' /proc/asound/cards)
[ -n "$CARD" ] || CARD=$(awk '$1 ~ /^[0-9]+$/ {print $1; exit}' /proc/asound/cards)
echo "-> using card $CARD ($(cat /proc/asound/card$CARD/id 2>/dev/null))"
aplay -l

section "device permissions"
ls -l /dev/snd/
command -v getfacl >/dev/null && getfacl -p /dev/snd/controlC$CARD 2>/dev/null

section "UCM (what PipeWire uses to pick outputs)"
alsaucm -c hw:$CARD list _verbs 2>&1 | head -20   # hw:N, not the card id: a bare id is looked up as a profile name

section "mixer controls BEFORE"
amixer -c $CARD scontents 2>&1 | grep -E "^Simple|Playback|Capture" | head -80

section "unmute and raise playback controls"
amixer -c $CARD scontrols | sed -E "s/^Simple mixer control '(.*)',([0-9]+)$/\1,\2/" | while IFS= read -r c; do
  case "$c" in
    Master*|Speaker*|Headphone*|PCM*|Front*|"Auto-Mute Mode"*|Line*|"Pre-Mixer"*|"Post-Mixer"*|*"Playback"*)
      if [[ $c == "Auto-Mute Mode"* ]]; then amixer -q -c $CARD sset "$c" Disabled && echo "  $c -> Disabled"
      else amixer -q -c $CARD sset "$c" 80% unmute 2>/dev/null && echo "  $c -> 80% unmuted" \
        || { amixer -q -c $CARD sset "$c" on 2>/dev/null && echo "  $c -> on"; }; fi ;;
  esac
done

section "mixer controls AFTER"
amixer -c $CARD scontents 2>&1 | grep -E "^Simple|Playback" | head -60

heard=no
try() {
  local label=$1; shift
  echo; echo ">>> Test: $label   (listen for 'front left, front right')"
  timeout 20 "$@" 2>&1 | tail -4
  local a=""
  # Plain stdin: under `su -c` there is no /dev/tty, but the terminal is still stdin.
  read -r -p ">>> Did you hear it? [y/N] " a || a=n
  echo "    answer: ${a:-n}"
  [[ $a =~ ^[Yy] ]] && heard=yes
}
section "playback tests"
for dev in 0 1 2 3; do
  [ -e /proc/asound/card$CARD/pcm${dev}p ] || continue
  try "card $CARD, device $dev, straight to the hardware ($(cat /proc/asound/card$CARD/pcm${dev}p/info 2>/dev/null | awk -F': ' '/^name/{print $2}'))" \
      speaker-test -D plughw:$CARD,$dev -c 2 -t wav -l 1
  [ $heard = yes ] && { echo "    -> heard on device $dev"; break; }
done
if [ $heard = yes ]; then alsactl store && echo "    mixer levels saved (alsactl store)"; fi

section "PipeWire's view (as $USER_NAME)"
su $USER_NAME -c "XDG_RUNTIME_DIR=/run/user/$USER_UID wpctl status" 2>&1 | head -40
su $USER_NAME -c "XDG_RUNTIME_DIR=/run/user/$USER_UID systemctl --user --no-pager status pipewire wireplumber" 2>&1 | grep -E "Active|●" | head -6

section "WirePlumber restarted with ALSA debug logging (user $USER_NAME)"
as_user() { su $USER_NAME -c "XDG_RUNTIME_DIR=/run/user/$USER_UID DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$USER_UID/bus $*"; }
as_user "systemctl --user set-environment WIREPLUMBER_DEBUG=spa.alsa:4,s-monitors:4,s-device:4,m-*:3,wp-device:4" 2>&1
since=$(date '+%Y-%m-%d %H:%M:%S')
as_user "systemctl --user restart wireplumber" 2>&1
sleep 4
as_user "wpctl status" 2>&1 | head -30
journalctl --since "$since" _UID=$USER_UID --no-pager -o cat 2>/dev/null | grep -vE "RTKit|UPower" | tail -80
as_user "systemctl --user unset-environment WIREPLUMBER_DEBUG" 2>&1

section "WirePlumber / PipeWire log this boot (user $USER_NAME)"
journalctl -b _UID=$USER_UID --no-pager -o cat 2>/dev/null | grep -iE "wireplumber|pipewire|spa\.|alsa|acp|ucm" | grep -vE "RTKit|UPower" | tail -60

section "kernel sound log"
journalctl -b -k --no-pager -o cat | grep -iE "sof|snd|hda|ALC|dmic" | grep -v X.509 | tail -30

sync
echo; echo "Report saved to $REPORT. Heard something: $heard. Back in Ubuntu, tell Claude 'report ready'."
