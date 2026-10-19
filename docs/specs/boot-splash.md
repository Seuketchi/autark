# Boot splash (design)

What you see between the firmware and the login screen: today a text console with a `PIN:` prompt from `autark-init` (see [autark-init.md](autark-init.md)). This is the design for replacing it with a loading screen that has the PIN box on it. **Design only; nothing is built.** It comes after the M4 qemu test, because it sits on top of `autark-init`.

## What it looks like

One screen, dark, the same family as the lock screen (`design/canvas/Lock.dc.html`) so the boot, the lock and the login read as one thing.

```
┌──────────────────────────────────────────────┐
│                                              │
│                                              │
│                  (Loop mark)                 │   the Loop logo, 72 px, sage
│                    Autark                    │
│                                              │
│                                              │
│            ┌──────────────────┐              │   only while the disk waits for a PIN
│            │  ● ● ● ●         │ →            │   dots, no characters
│            └──────────────────┘              │
│              Enter your disk PIN             │   or "Wrong PIN. 2 tries left."
│                                              │
│                   ─────                      │   progress bar when there is no prompt
└──────────────────────────────────────────────┘
```

| Part | Value |
| --- | --- |
| Background | `#1E1C18` (the Linen dark sky). Fixed dark: the theme lives on the root file system, which isn't mounted yet |
| Mark | the **Loop** logo (`M5.5 19.5L12 4.5l6.5 15C14.5 16 9.5 16 5.5 19.5z`, 2.4 stroke) in sage `#4F7561`, centred 40% down |
| Name | "Autark", Geist 600, `#ECE8E1`, under the mark |
| PIN box | 260 × 40, fully rounded, `rgba(236,232,225,0.14)`, one dot per key typed; Backspace removes one, Enter submits |
| Messages | 13 px `#B5AEA3`; errors in the same colour with the text only ("Wrong PIN. 2 tries left."), no red flash |
| Waiting | a slow 2.4 s pulse of the mark's opacity (0.55 → 1) while the TPM works or root mounts; a thin progress bar only if it takes over 3 s |
| Fonts | one font compiled into `autark-init` (a subset of Geist: the letters of the fixed messages and digits, ~30 KB) |

States, in order: **starting** (mark pulses) → **PIN** (box appears, mark stays) → **checking** (box dims, pulse) → **wrong** (box shakes once, message, box clears) → **opened** (mark stops pulsing, holds 200 ms) → handed to systemd. A **passphrase** fallback uses the same box with the message "Enter your recovery passphrase" and shows dots the same way. Escape on the PIN box shows the console log instead (a debug path; also what appears if drawing fails).

## How it is drawn

The kernel already gives the initramfs a screen: `CONFIG_SYSFB_SIMPLEFB`, `CONFIG_DRM_SIMPLEDRM` and `CONFIG_DRM_FBDEV_EMULATION` are built in, so the firmware's framebuffer is `/dev/fb0` before any module loads. `i915` and `xe` are modules and load later, in the real system.

- **Draw** with `mmap` on `/dev/fb0`, software rendering into a back buffer, then copy. Shapes are rectangles, rounded rectangles and the logo path, so a small hand-written rasteriser is enough (a drawing crate would be one more thing to vendor and check for the initramfs); no GPU, no libdrm, no Plymouth.
- **Keys** come from the console, the same way the text prompt reads them today: the terminal goes into raw mode, no echo. No evdev, no keyboard layout code. (US layout only for digits in a PIN; the disk passphrase is typed on the layout the kernel console has.)
- **Fits behind the `Console` trait** in `crates/autark-init/src/console.rs`: `say`, `secret` and `wait_for_enter` map onto "message", "PIN box" and "press a key". The unlock logic and its 26 tests do not change; `Terminal` stays as the fallback and the test double.
- **Fallback is automatic**: no `/dev/fb0`, a mode it can't map, or `autark.splash=0` on the kernel command line gives today's text prompt. A splash that can't draw must never stand between you and your disk.
- **The hand-over** is the one rough edge: when `i915` or `xe` loads in the real system, the screen is re-initialised and may flash once. The next thing on screen (the login, once it exists as a graphical screen; today it is a text `getty`) should start from the same background colour, so it reads as a short blink, not a change of scene. Avoiding it entirely would mean loading the GPU driver in the initramfs, which is a different (larger) job and not part of this.

## Quiet boot

The splash is only calm if the kernel is. The kernel command line (`/etc/kernel/cmdline`) gets `quiet loglevel=3 vt.global_cursor_default=0` once the splash works; without a working splash it stays as it is, so errors remain visible. `autark.splash=0` brings the text back and `Escape` shows the log for one boot.

## Order of work

1. M4 qemu test passes (the bundle is built; the run needs the Ubuntu partition).
2. A `Console` implementation that draws to a framebuffer: the background, the mark, the PIN box, tested in qemu by comparing the framebuffer to a reference image.
3. The same on the laptop through the `try` entry (a one-time boot; the next boot is dracut).
4. Make it the default only after a week of `try` boots behaving.

## Decisions to make

| Question | Recommendation |
| --- | --- |
| Dark only, or follow the theme? | Dark only. The theme is on the encrypted disk |
| Show the PIN length as dots, or a plain box? | Dots, one per key. No hint of the PIN's length beforehand |
| Animate the mark? | A slow pulse only. The reduced-motion setting is on the encrypted disk and can't be read yet, so the pulse is the only movement and it stops once the PIN box is up |
| A language other than English? | Not now; the messages are six fixed strings |
