# Boot splash (design)

What you see between the firmware and the login screen: today a text console with a `PIN:` prompt from `autark-init` (see [autark-init.md](autark-init.md)). This is the design for replacing it with a loading screen that has the PIN box on it. **Status: written, tested, and working on the laptop's real screen (2026-10-20, through the Rust-init test boot).** It is off unless the kernel command line has `autark.splash=1`, so the default boot is unchanged. It sits on top of `autark-init`.

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
| Messages | 14 px `#B5AEA3`; errors in the same colour, no red flash. The words are the ones `autark-init` already says ("That PIN isn't right."); a count of tries left needs the unlock code to pass it on and is not done |
| Waiting | a slow 2.4 s pulse of the mark's opacity (0.55 → 1) while the TPM works or root mounts; a thin progress bar only if it takes over 3 s |
| Fonts | Geist Regular and SemiBold, pre-drawn by `autark-splash-font` into two 70 KB alpha-mask files compiled into `autark-init` (printable ASCII, `…` and `’`); no font library in the initramfs |

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

## What is built

In `autark-tools`, `crates/autark-init/src/splash/`: `canvas.rs` (rounded boxes, circles, the mark's outline, soft edges), `font.rs`, `scene.rs` (the five states), `fb.rs` (maps `/dev/fb0`, any 32-bit channel order), `entry.rs` (what each key does to the secret: Backspace, Ctrl+U, arrow keys ignored, UTF-8), and `console.rs` (the `Console` that `autark-init` uses when the screen allows it, with a thread repainting about 30 times a second). 35 unit tests, including a fake screen that checks the frames drawn while a PIN is typed.

To look at every state without booting: `cargo run --release -p autark-init --bin autark-init-splash-preview -- <folder> [1920x1080]` writes one PPM picture per state. To redo the font files: `cargo run --release -p autark-splash-font -- crates/autark-init/assets`.

Not done: the box shake on a wrong PIN, "Escape shows the log", and the tries-left count.

### Two things the real screen taught

- **The firmware logo stays until the console takes over.** The kernel is built with `CONFIG_FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER=y`, so the screen keeps showing the MSI logo until the console prints its first real text; the kernel's dummy console ignores blank-only output, so `ESC[2J` alone does nothing. `SplashConsole` therefore prints `ESC[2J ESC[H . ESC[?25l` first (a real character, then hides the cursor) and only then starts painting; the log shows `fbcon: Taking over console` before the first frame. Without it the first test boot sat on the MSI logo.
- **Why a splash that doesn't draw is debugged from a log, not a screen.** See "Debugging a test boot" in [autark-init.md](autark-init.md): `autark.log=<ESP device>` keeps a synced log on the ESP.

## Order of work

1. M4 qemu test passes (the bundle is built; the run needs the Ubuntu partition).
2. ✅ A `Console` that draws to a framebuffer: the background, the mark, the PIN box; tested against a fake screen. Still to do: in qemu, with a graphical window, to see it.
3. ✅ The same on the laptop through the `try` entry (a one-time boot; the next boot is dracut), with `EXTRA_CMDLINE="autark.splash=1 quiet loglevel=3 vt.global_cursor_default=0"` for `uki`, which adds them to that entry's command line only.
4. Make it the default only after a week of `try` boots behaving.

## Decisions to make

| Question | Recommendation |
| --- | --- |
| Dark only, or follow the theme? | Dark only. The theme is on the encrypted disk |
| Show the PIN length as dots, or a plain box? | Dots, one per key. No hint of the PIN's length beforehand |
| Animate the mark? | A slow pulse only. The reduced-motion setting is on the encrypted disk and can't be read yet, so the pulse is the only movement and it stops once the PIN box is up |
| A language other than English? | Not now; the messages are six fixed strings |
