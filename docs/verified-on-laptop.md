# Checked on the laptop

Things that were tried by hand on the MSI Cyborg 15 and what happened. ✅ = worked as intended, ⬜ = not checked yet. Boot-chain checks (TPM, splash, the Rust init) are in [specs/autark-init.md](specs/autark-init.md).

## 2026-10-20

| Check | How | Result |
| --- | --- | --- |
| Lock screen | Super+L (`autark-lock` runs as a daemon from Wayfire's autostart) | ✅ it shows, and the login password unlocks it |
| Screenshot and paste | a screenshot key (`autark-shot`), then Ctrl+V into a window that takes images | ✅ the image arrived |
| Mic-mute key | the Fn mic key (`KEY_MICMUTE` → `autark-osd mic mute`), once each way, with the command logging each run | ✅ one run per press; the pop-up ("muted" / "unmuted") matched `wpctl get-volume @DEFAULT_AUDIO_SOURCE@` both ways |
| Charge limit | read from `/sys/class/power_supply/BAT1/` (`msi-ec` provides it) | ✅ the limit is **80%** (`charge_control_end_threshold`), charging resumes below 70%. A battery at 85% reads "Not charging": it was charged past 80 earlier and discharges down to 70 first |

### Fn keys

| Key | What it sends | What it does now | Result |
| --- | --- | --- | --- |
| Fn+F4 (touchpad) | Ctrl+Super+F24 (a known chord, no mapping needed) | `autark-osd touchpad` switches the touchpad off and on through the root helper (the kernel's `inhibited`, touchpads only) | ✅ pop-up "Touchpad off" / "Touchpad on" |
| Fn+F6 (Bluetooth) | the unknown scancode `0xd7`; `hardware/target/udev/70-autark-keyboard.hwdb` maps it to `KEY_BLUETOOTH` | `autark-osd bluetooth` powers the adapter off and on through BlueZ | ✅ |
| Fn+F11 (projection) | Super+P (plus an unknown `0xc0` that does nothing) | `autark-osd screens` → `autark-displays project`: laptop screen only → both → other screen only | ✅ with one screen ("no other screen is connected"); ⬜ with a second screen |

How they were identified: a guided probe (`libinput debug-events` with the kernel log, one key at a time). Guessing from the kernel's "unknown key" lines alone was wrong once: it put the touchpad on F6, which switched the touchpad off until the mapping was corrected. The keys, scancodes and bindings are in `~/.config/wayfire.ini` (`binding_autark_touchpad`, `_bluetooth`, `_project`) and `scripts/msi-keys-hwdb.sh install` puts the mapping in place.

The mic key looked wrong once (pop-up "unmuted", `wpctl` still `[MUTED]`). It could not be reproduced with the key's command logged: every press ran the command once and every pop-up matched the real state. Most likely an extra press landed between the pop-up and the read.

## Not checked yet

- ⬜ `msi-ec` loading by itself at boot. It has no alias, so `scripts/autark-kernel-post.sh install` adds `/etc/modules-load.d/msi-ec.conf` (2026-10-20); look at `lsmod | grep msi_ec` after the next reboot.
- ⬜ Setting a fan mode or shift mode (the controls are there under `/sys/devices/platform/msi-ec/`; none has been set yet).
- ⬜ The area screenshot (Shift+PrtSc).
- ⬜ One scancode nothing handles is left: `0x8e`. Which physical key it is is not known (Fn+F4, F6 and F11 are accounted for above).
- ⬜ Fn+F11 (projection) with a second monitor connected: press it three times and watch the panel and the monitor switch.
- ⬜ NVIDIA 3D and Vulkan. The `nouveau` driver loads and the GPU suspends; 3D needs Mesa rebuilt with NVK.
- ⬜ Keyboard RGB (blocked).
