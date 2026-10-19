# 8b report (Autark side)

## 2026-10-19 09:16 pkg_rust FAILED (attempt 1)
- ran: phase8b-inside.sh; Rust bootstrap, 26s in
- result: panic at src/bootstrap/src/core/sanity.rs:323: FileCheck executable "/usr/bin/FileCheck" does not exist
- cause: external LLVM (8a) doesn't install FileCheck; bootstrap requires it when [rust] codegen-tests is on (the default)
- fix: codegen-tests = false in the bootstrap.toml heredoc (no tests are run anyway)
- diff:
    --- phase8b-inside.sh	2026-10-19 09:09:46.639838829 +0800
    +++ /tmp/claude-1000/-home-tan/c3f563ef-08d9-444a-8ff4-97ecae6266e5/scratchpad/phase8b-inside.sh	2026-10-19 09:16:37.378063763 +0800
    @@ -139,6 +139,8 @@
     lto = "thin"
     codegen-units = 1
     llvm-bitcode-linker = false
    +# [Autark] no tests are run, and 8a's LLVM does not install FileCheck; bootstrap panics on a missing external FileCheck unless codegen-tests is off.
    +codegen-tests = false
     
     [target.x86_64-unknown-linux-gnu]
     llvm-config = "/usr/bin/llvm-config"

## 2026-10-19 10:15 attempt 2 and later
- 09:32 unexplained hard reset mid Rust build (no shutdown/panic/OOM in journal; thermal zones 56-76C). Rebuilt with the fix.
- 10:13 phase 8b done: rustc/cargo 1.97.1, gtk4 4.22.4, gtk4-layer-shell 1.3.0, sudo-rs 0.2.15. 18 autark-* binaries in /usr/bin.
- autark-bar links libgtk4-layer-shell first. polkit/upower are D-Bus activated (inactive until used), not a fault.
- test-failures.txt (from earlier phases only): vim, systemd, e2fsprogs, libjpeg-turbo; nothing from 8b.
- Step 9: source in ~/autark-tools (git init, vendored cargo config). Each of bar, dock, launcher, wallpaper, notifyd, lock ran 5s on wayland-1 with no stderr and no crash. NOT visually confirmed. No autostart entries added yet.
- Note: wayfire.ini still has autostart_wf_shell = true (borrowed wf-shell).

## 2026-10-19 10:22 step 9
- On wayland-1 (Wayfire): autark-bar, dock, wallpaper, notifyd, launcher all run; screenshot confirms bar, dock, wallpaper, launcher render. wf-shell not running.
- stderr: only GTK a11y bus warning (harmless; GTK_A11Y=none silences) and bar logs org.autark.AI1 ServiceUnknown (autark-ai D-Bus service not installed/activatable; bar tolerates it).
- autostart added to ~/.config/wayfire.ini (backup .bak-8b): bar, dock, wallpaper, notifyd. Launcher not autostarted (shows on launch; toggled by Super+Space). autark-lock not tested after earlier blind run; unexplained 💥 + user reboot at 10:18.
- No autark-tools source fixes needed so far.

## 2026-10-19 10:23 other tools
- Ran settings, files, notes, monitor, power, stats on wayland-1: all start and stay up; monitor (Activity) window renders correctly (screenshot). displays/nightlight/pkg are CLIs (usage printed), not tested further.
- Cosmetic: settings/files/notes/monitor emit 6-14 Gtk-CRITICAL "gtk_icon_theme_lookup_by_gicon: assertion 'size > 0' failed" at startup (a gicon Image created before a pixel size is set); no functional effect seen. Dock shows a generic gear icon for these apps (no matching icon/.desktop). Not fixed; no source changes made.

## 2026-10-19 10:26 fix: icon CRITICALs
- cause: window-control button images styled -gtk-icon-size: 0 (to hide the glyph in the dot buttons); GTK asserts size > 0, 3 buttons x 2 asserts = 6 per window
- fix: -gtk-icon-size: 1px in files.css, monitor.css, settings.css, notes.css (one line each); patch in ~/autark-tools-fixes.patch

## 2026-10-19 10:28 autostart verified
- After logout/login (wayfire pid 8496): autark-bar, dock, notifyd, wallpaper all started at 10:27:49 by autostart; no wf-shell.
- Login journal noise (not fixed): login[] oo7-pam: "Failed to connect to daemon socket /run/user/1000/oo7-pam.sock" (oo7-daemon not up at tty login; pam line is optional so login works, but keyring will not auto-unlock); wireplumber: UPower percentage NameHasNoOwner (race, upower is D-Bus activated), BlueZ not available (bluez not built), ALSA /dev/snd/seq permission denied and hw:0 control missing.

## 2026-10-19 10:29 autark-lock FAILS on password submit
- User ran autark-lock in foot and entered the password. 10:28:54 journal: "pam_unix(autark-lock:account): setuid failed: Operation not permitted", then kernel: autark-lock segfault at 208 in libgtk-4.so.1.2200.4 (null-pointer deref), core dumped (coredumpctl, pid 8730).
- Not resolved: no gdb/lldb here for a backtrace. NoNewPrivs=0, unix_chkpwd is setuid root, /etc/pam.d/autark-lock includes system-auth/system-account (expected). Crash is in the submit path (crates/autark-lock/src/main.rs:293-317, auth.rs: PAM runs on a std::thread, result handled via glib::spawn_future_local).
- Hypothesis (unverified): PAM acct_mgmt/auth fails (setuid EPERM) so check() returns false and the 'wrong password' branch touches widgets that GTK already dropped; or PAM on a non-main thread misbehaves. Needs a debugger or a debug build with RUST_BACKTRACE/ASan.
- Lock must NOT be used as the real lock until fixed (session stays locked if the client dies; escape = tty2, pkill wayfire).

## 2026-10-19 10:32 autark-lock crash: cause found, fix built (untested)
- Correction to previous entry: PAM was fine. The "setuid failed" line is a harmless pam_unix account warning; acct_mgmt returns Ok (verified with a standalone pam_client test); a wrong password just fails cleanly. The password was RIGHT; the crash is on successful unlock.
- Backtrace (temp SIGSEGV handler, debug build): instance.unlock() -> clear_lock_state -> gtk_window_destroy -> gtk_application_window_removed -> gdk_wayland_toplevel_remove_from_session -> SEGV (null deref). Cause: lock windows were gtk::ApplicationWindow on ext-session-lock surfaces; GTK 4.22.4 treats them as toplevels in app sessions and dereferences NULL when they are destroyed.
- Fix: crates/autark-lock/src/main.rs window() uses gtk::Window::new() instead of ApplicationWindow::new(app) (2 lines, [Autark] comment). Patch in ~/autark-tools-fixes.patch. Built in target/release, not installed, retest pending.

## 2026-10-19 10:33 autark-lock fix verified
- Fixed build (target/release/autark-lock, 10:32): wrong password at 10:33:02 rejected (auth failure), correct password at 10:33:06 unlocked; no segfault, no new coredump, process exited cleanly.
- Not yet installed to /usr/bin.

## 2026-10-19 10:34 installed + lock daemon autostart
- Installed fixed autark-lock/files/notes/settings/monitor to /usr/bin (identical to target/release).
- Added autark_lock = autark-lock --daemon to wayfire.ini [autostart] (daemon locks on logind request and before sleep). Previous backup: wayfire.ini.bak-8b (without this line).
placeholder icons written to ~/autark-icons (F/N/S/A, rounded squares); install needs root

## 2026-10-19 10:39 Kith / autark-ai
- autark-ai runs fine by hand on the session bus (org.autark.AI1 methods answered; AI is off until enabled = true in ai.toml, so no Ollama needed to start). The bar's "ServiceUnknown" only means nothing activates it.
- Added crates/autark-ai/data/org.autark.AI1.service (session bus activation, Exec=/usr/bin/autark-ai). Install: su -c 'install -Dm644 /home/tan/autark-tools/crates/autark-ai/data/org.autark.AI1.service /usr/share/dbus-1/services/'. Build script has no step for it yet.
- Ollama is not installed; model choice left to the user (config comment: "pick one after measuring it on your laptop").

## 2026-10-19 10:41 keybindings and launcher
- wayfire.ini [command] still had stock placeholders: launcher bound to foot, lock to swaylock (not installed), logout to wlogout (not installed). Changed: Super+Space -> autark-launcher (single-instance, toggles), Super+Shift+Esc -> autark-lock; autostart autark-launcher --daemon (hidden). Terminal: foot on Super+Enter (unchanged, works). Logout binding (wlogout) still dead; use pkill wayfire or an autark-power entry.

## 2026-10-19 10:42 more daemons
- README says nightlight, displays and power daemons start with the session. autark-nightlight daemon runs (status: "off (set times)" by day). Added autark_nightlight and autark_displays (daemon) to wayfire.ini [autostart]. autark-displays list needs its daemon (org.autark.Displays1).
- autark-power NOT autostarted: defaults sleep the laptop after 10 min idle on battery (30 plugged in) and lock when screens go off; that would interrupt long builds. Left for the user to decide.
- wayfire.ini has a stock 'outputs = kanshi' autostart (kanshi not installed, harmless; displays daemon docs say to leave outputs out of wayfire.ini).
- Dock default pins "galley" (probably the user's own terminal) but no galley is in autark-tools; user's repo github.com/Seuketchi/autark is private (404). SSH key generated (~/.ssh/id_ed25519, no passphrase); not yet added to GitHub, git name/email unset.

## 2026-10-19 10:43 hotkeys
- User: Win+D did nothing. Cause: no [wm-actions] toggle_showdesktop binding in wayfire.ini (plugin loaded, binding unset). Added toggle_showdesktop = <super> KEY_D.
- Stock [command] entries pointed at missing tools: grim/slurp (screenshots), light (brightness). Changed screenshots to autark-shot, volume/mute from amixer to wpctl; added README keys: Super+Shift+3/4/5 shots, Super+K Assistant, Ctrl+Alt+Esc force quit. Brightness keys still call missing 'light' (no CLI in autark-tools; Settings handles brightness via logind). Backup: wayfire.ini.bak-8b-keys.

## 2026-10-19 10:51 browser (phase 8c) prepared
- Chosen: WebKitGTK 2.54.1 (GTK4, Wayland only, no video/audio first) + Epiphany 51.1. Plan: ~/browser-src/PLAN.md. Tarballs in ~/browser-src/dl (26 + gsettings-desktop-schemas), SHA256SUMS next to them. GNOME tarballs verified against download.gnome.org .sha256sum; webkitgtk matches webkitgtk.org .sums; the rest are hash-recorded only (no PGP check; no gpg here).
- Script: ~/browser-src/phase8c-inside.sh (untested; 26 packages: icu, libgpg-error, libgcrypt, libxslt, libwebp, ruby, brotli, woff2, nghttp2, libunistring, nettle, gnutls, libsoup, glib-networking, libsecret, libseccomp, bubblewrap, xdg-dbus-proxy, unifdef, libarchive, gsettings-desktop-schemas, json-glib, libportal, gcr, libadwaita, webkitgtk, epiphany). Needs tarballs + script copied to /sources (root).

## 2026-10-19 11:03 desktop menu, Activity empty
- autark-wallpaper: right-click menu on the desktop (Change Wallpaper, Display Settings, Open Files, Activity, Settings), gtk::GestureClick secondary + Popover; built in target/release, not installed. Needs a real-screen test.
- Activity (autark-monitor) was empty: org.autark.Stats1 is served by autark-stats but nothing activates it (earlier it only worked because it was started by hand). Added crates/autark-stats/data/org.autark.Stats1.service (session bus activation). Install: su -c 'install -Dm644 /home/tan/autark-tools/crates/autark-stats/data/org.autark.Stats1.service /usr/share/dbus-1/services/'. Workaround for now: autark-stats left running.
- Hotkey: Ctrl+Shift+Esc opens Activity.

## 2026-10-19 11:07 phase 8c extended (user chose WebKitGTK+Epiphany, "add everything it's missing")
- Firefox download deleted (was started without the user's say-so; user chose option 1).
- Added: nasm, libogg, libvorbis, opus, libvpx, dav1d, libavif, ffmpeg 8.1.3 (GitHub tag; ffmpeg.org unreachable), orc, gstreamer + plugins base/good/bad + gst-libav 1.28.8, hunspell, enchant + LibreOffice en_US dictionary, hyphen, at-spi2-core, libevdev, libmanette. WebKit now has video/audio/MSE, spellcheck, AVIF, hyphenation, gamepad on. Still off: JPEG-XL, WebRTC, geolocation, speech, WebXR, GStreamer GL.
- 46 packages in ~/browser-src/phase8c-inside.sh (syntax-checked, never run). 49 files in ~/browser-src/dl, hashes in ~/browser-src/SHA256SUMS (GNOME ones verified against publisher sums; the rest recorded only).

## 2026-10-19 11:13 8c first run: woff2 failed
- Done before it: icu, libgpg-error, libgcrypt, libxslt, libwebp, ruby, brotli.
- pkg_woff2 FAILED at configure: "Compatibility with CMake < 3.5 has been removed from CMake" (CMakeLists.txt:10, cmake_minimum_required in woff2 1.0.2). Cause: CMake 4 drops support for policy versions below 3.5; woff2's top-level file asks for older.
- Fix: -D CMAKE_POLICY_VERSION_MINIMUM=3.5 on woff2's cmake line (phase8c-inside.sh, [Autark] comment).
- Also prepared phase8d-inside.sh (fmt, simdutf, VTE 0.84.1 for autark-terminal); separate .track file so it can't clash with 8c. Not to be run while 8c runs.

## 2026-10-19 11:15 8c second run: woff2 failed again (compile)
- After the cmake policy fix, woff2 configured and compiled 7 of 26 objects, then: include/woff2/output.h:79 "'uint8_t' does not name a type" (and follow-on 'buf_' not declared in woff2_out.cc).
- Cause: woff2 1.0.2's headers use uint8_t without #include <cstdint>; current GCC no longer includes it transitively.
- Fix: -D CMAKE_CXX_FLAGS="$CXXFLAGS -include cstdint" on woff2's cmake line. This is woff2's second failure in a row on the same package.

## 2026-10-19 11:19 Kith: Ollama prepared
- ai.toml (user's, made 10:54 by Settings): enabled = true, local_only = true. No Ollama or model existed.
- User asked for "deepseek flash"; the only Ollama build is deepseek-v4.1-flash:cloud (552B MoE on Ollama's servers, needs an account, sends prompts off-laptop). Conflicts with local_only = true, so not used. User then said "you decide on the model": chose gemma3:4b (local, ~3.3 GB, no thinking mode, CPU-only i5-13420H/23 GB). To be measured on this laptop.
- Ollama v0.40.6 official release downloaded to ~/ollama-dl, sha256 verified against the release sha256sum.txt. Models stored in /var/lib/ollama/models (on /; /home has only ~5 GB free). Install script: ~/ollama-dl/install-ollama.sh (root).

## 2026-10-19 11:21 8c: libsecret failed (first failure for this package)
- "mkdir: cannot create directory 'build': File exists". Cause: libsecret's release tarball ships a top-level build/ folder, so meson_build's own mkdir build collides.
- Fix: all packages in phase8c/8d now use autark-build for the out-of-tree build dir (mkdir -p autark-build; cd autark-build) instead of build. woff2 had passed by then (so the cstdint fix worked).

## 2026-10-19 11:22 Kith running on gemma3:4b
- Ollama 0.40.6 service up (127.0.0.1:11434), gemma3:4b pulled (3.4 GB, /var/lib/ollama/models). ~/.config/autark/ai.toml: enabled, local_only, [ollama] model = "gemma3:4b". Models() returns it.
- Check (built-in rules): instant, "rm -rf ~/projects" -> risk 1.0 "deletes folders and everything in them".
- Route "turn the volume down a bit and open files": first call timed out at busctl's 25 s (cold model load), second 11.5 s (warm, CPU-only). Right action (set_volume 20, conf 0.9) but the model invented an unrequested daily 08:00 'open_app' task and missed 'open files' as an action. 11 s is slow for the launcher.

## 2026-10-19 11:23 8c: unifdef failed (first failure)
- unifdef.c:205 "'constexpr' in empty declaration" etc. Cause: unifdef 2.12 uses constexpr as a variable name; it is a keyword in C23, which GCC now defaults to.
- Fix: make ... CFLAGS="$CFLAGS -std=gnu17" on both make lines ([Autark] comment).
- libsecret, libseccomp, bubblewrap, xdg-dbus-proxy had passed before it (autark-build fix worked).

## 2026-10-19 11:27 8c: libportal failed (first failure)
- meson: Unknown option "backends" (libportal 0.11.0 has backend-gtk3/gtk4/qt5/qt6 as features). Fix: -D backend-gtk4=enabled and the other three disabled.
- Cause: I wrote the option from memory of an older libportal. Cross-checked every meson -D name and value type in phase8c/8d against the tarballs' meson_options: only orc was also wrong (gtk_doc; it is hotdoc), fixed too, before it could fail.

## 2026-10-19 11:34 Kith improvements (autark-ai, gemma3:4b)
- Before: "mute" -> no action + invented remember ("Works on Autark in the evenings", copied from the prompt's own example) + invented daily task; "dim the screen" likewise; ~13 s per call; "what is the capital of france" hung to the 120 s timeout.
- Causes: (1) task/remember were always in the schema and prompt, so the small model filled them in; (2) every extra field is generated tokens on CPU (~13 s); (3) the model degenerates inside unbounded strings under grammar-constrained decoding; (4) cold model load > busctl's 25 s.
- Changes (crates/autark-ai): route.rs offers remember/task (schema and prompt) only when the sentence has cue words (wants_task / wants_remember); dropped the leaking example; added 3 few-shot examples; question maxLength 240 and truncated at the first '?'. ollama.rs: keep_alive 30m, num_predict 400 cap on structured calls. Unit tests: 25 pass.
- After: mute 2.6 s warm (correct), volume/brightness/lock+wifi correct, 8-10 s; no phantom tasks/remember on plain commands; question-type input 8-23 s and correct.
- Still weak: a scheduled-task sentence ("every morning at 8 summarise my build log") also gets a bogus open_app action; "turn the volume down a bit and open files" is unreliable. 4B CPU model limit. Binary not installed to /usr/bin (target/release only).

## 2026-10-19 11:38 8c: gcr failed (first failure)
- meson.build:65 "Program 'gpg2 gpg' not found": gcr 4.4.1 looks for gpg unless -D gpg_path is given.
- Cause: no GnuPG on Autark. Fix: -D gpg_path=/usr/bin/gpg (only gcr's GnuPG key listing uses it at run time; Epiphany doesn't).

## 2026-10-19 11:50 8c: autark runs it itself (sudo rule); AppStream needs itstool
- Setup: tan can run the 8c script and update it via a sudoers rule (/etc/sudoers.d/8c-build); the first version of the rule, made from a wrapped paste, was malformed and allowed an unrestricted cp as root for a few minutes until fixed. The script now stages its own tarballs from ~/browser-src/dl into /sources and verifies SHA256SUMS.
- AppStream: display-detection is a combo (auto/none/wayland): set none. Then data/meson.build:27 'Program itstool not found': itstool imports libxml2's Python bindings (gone since libxml2 2.14). libadwaita 1.8 and 1.9 both require appstream (Epiphany 51 needs libadwaita >= 1.8), so it cannot be dropped. Fix: stub itstool (copies the metainfo untranslated) on PATH for that one package only.

## 2026-10-19 11:52 8c: libadwaita needs sassc
- libadwaita 1.9.4: subprojects/sassc 'Dependency libsass is required but not found' (fallbacks are off). Fix: build libsass 3.6.6 and sassc 3.6.2 first (BLFS recipe; libsass gets -include cstdint up front, same GCC issue as woff2).

## 2026-10-19 11:55 8c: libavif needs libyuv or it switched off
- cmake: "Cannot find libyuv ... pass -DAVIF_LIBYUV=LOCAL or OFF". Fix: -D AVIF_LIBYUV=OFF and AVIF_LIBSHARPYUV=OFF (not available here; libavif uses its own conversion). libsass, sassc, libadwaita, libvpx, dav1d, nasm, ogg, vorbis, opus passed before it.

## 2026-10-19 12:03 8c: libmanette needs hidapi
- meson: Dependency "hidapi-hidraw" not found. Fix: build hidapi 0.15.0 (CMake, hidraw backend only) before libmanette. 49 packages were done by then, including ffmpeg, GStreamer and plugins, libadwaita, appstream, libavif.

## 2026-10-19 12:04 8c: WebKitGTK configure needs HarfBuzz with ICU
- cmake: "Could NOT find HarfBuzz (missing: ICU (required))". Cause: 8b built HarfBuzz with icu=disabled (ICU did not exist yet); WebKit needs libharfbuzz-icu.
- Fix: new package harfbuzz-icu rebuilds the same tarball with 8b's options plus icu=enabled (same soname, replaces the installed copy). 53 packages done before it (everything up to WebKitGTK itself, with hidapi/libmanette passing).

## 2026-10-19 12:07 8c: WebKitGTK configure: speech synthesis
- cmake OptionsGTK.cmake:345 "Either USE_SPIEL or USE_FLITE is needed for ENABLE_SPEECH_SYNTHESIS" (it is on by default; I had turned both backends off). Fix: -D ENABLE_SPEECH_SYNTHESIS=OFF.
- Rehearsed the full configure as tan in a scratch dir before the root run: passes, summary shows VIDEO, WEB_AUDIO, GAMEPAD, SPELLCHECK, AVIF, LIBHYPHEN, WOFF2, LCMS, GSTREAMER, BUBBLEWRAP_SANDBOX on.

## 2026-10-19 12:08 8c: WebKitGTK compile stopped at step 61/8912: Ruby missing psych
- FAILED JavaScriptCore/DerivedSources/JSCWebPreferenceOptions.h: GeneratePreferences.rb does 'require yaml' -> "cannot load such file -- psych". Cause: I built Ruby without libyaml on the wrong assumption that WebKit would not use YAML (my own comment in the script said so).
- Fix: libyaml 0.2.5 then Ruby again (package ruby-psych, same tarball). Checked the other Ruby requires in WebKit's scripts (optparse, fileutils, digest, json, erb, getoptlong, strscan, date...): all stdlib/bundled in Ruby 3.4.

## 2026-10-19 12:16 WebKitGTK: overheating, paused, resumed with fewer jobs
- At step 2728/8912 with JOBS=6 plus another cargo build (not started by me) a zone hit 97 C (acpitz firmware zone 93 C earlier). Root processes can't be signalled with the sudo rule, so the user paused them (pause8c.sh: SIGSTOP on cc1plus/cc1/ld/as), then stop8c.sh (SIGINT to ninja, SIGCONT, kill script).
- Script change: build() override keeps and resumes a package tree that already has autark-build/build.ninja (the library build() always rm -rf'd it); JOBS default 6 -> 4. Watcher threshold 90 -> 88 C.

## 2026-10-19 12:28 Firefox binary + what it needs (decision: both browsers)
- User agreed to: official Firefox binary now, WebKit/Epiphany source build continues. Firefox 158.0 linux-x86_64 en-US tarball downloaded to ~/ff-bin, sha256 verified against archive.mozilla.org SHA256SUMS (no PGP check).
- ldd shows it needs GTK3 and the X11 client libs even for Wayland (libX11, X11-xcb, xcb, xcb-shm, Xext, Xfixes, Xcomposite, Xdamage, Xcursor, Xrandr, Xrender, Xi). Added to phase8c (before webkitgtk): util-macros, xorgproto, xcb-proto, libXau, libXdmcp, libxcb, xtrans, libX11, libXext, libXfixes, libXrender, libXcomposite, libXdamage, libXcursor, libXrandr, libXi, libXinerama, GTK3 3.24.43 (X11 + Wayland backends; the binary imports gdk_x11_* symbols). WebKit build was stopped cleanly to run these first; its tree is kept and resumes.

## 2026-10-19 12:31 8c: GTK3 needs cairo-xlib
- All 17 X11 packages built. GTK3 meson.build:506: Dependency "cairo-xlib" not found. Cause: cairo was built in 8b before any X library existed (options: release, tests=disabled, rest auto).
- Fix: package cairo-x11 rebuilds the same tarball with the same options (auto now picks xlib/xcb), before gtk3.

## 2026-10-19 12:32 8c: GTK3 compile needs epoxy/glx.h
- cairo-x11 rebuilt fine. GTK3 compile: gdk/x11/gdkglcontext-x11.h: fatal error: epoxy/glx.h. Cause: 8b built libepoxy with glx=no, x11=false (no X then). Fix: package libepoxy-glx (same tarball, glx=yes, x11=true), before gtk3.
- Lesson: anything 8b built X-less that X-using software now needs (cairo, libepoxy, harfbuzz-icu earlier) has to be redone; I should have grepped the 8b logs for 'x11'/'xlib' = no before starting.

## 2026-10-19 12:37 Firefox 158.0 binary tested, install script ready
- With GTK3, the X11 client libs, cairo-x11 and libepoxy-glx installed, ldd of libxul/firefox/libmoz* shows nothing missing. Headless test as tan (MOZ_ENABLE_WAYLAND=1): loaded https://example.com and rendered the screenshot correctly (TLS and fonts work); CJK text shows tofu, no CJK font on Autark.
- ~/ff-bin/install-firefox.sh (root): re-checks the sha256, installs to /opt/firefox, /usr/bin/firefox launcher (Wayland on), desktop entry and hicolor icons. Not yet run. No autark-sandbox profile written yet.

## 2026-10-19 13:52 8c: WebKitGTK compile error in VideoFrameGStreamer (step 5241/5934)
- FAILED UnifiedSource-platform-62.cpp.o: VideoFrameGStreamer.cpp:821 'DMABuf' is not a member of MemoryType; :851 gst_dmabuf_memory_get_fd not declared.
- Cause: my choice USE_GSTREAMER_GL=OFF with USE_GBM=ON is an untested combination in 2.54.1: the DMABuf enumerator (header) and #include <gst/allocators/gstdmabuf.h> (cpp) exist only under USE(GSTREAMER_GL), but getDMABuf() and its caller are guarded by USE(GBM) alone.
- Fix: idempotent source patch at the start of pkg_webkitgtk (enumerator and include whenever GBM is on). Chosen over turning GSTREAMER_GL on because that flips cmakeconfig.h and would recompile nearly all 5934 steps; the patch recompiles only the files that include the header. Hardware-GL video paths stay off either way.
- The thermal guard worked: 4 pauses at 89-93 C, resumed at 70-73 C.

## 2026-10-19 13:57 desktop starts on login
- User: "every boot we have to do ... use the terminal before entering this gui". Autark boots to a getty on tty1 (no display manager); Wayfire had been started by hand as plain 'wayfire'.
- ~/.bash_profile now execs wayfire for a login on tty1 when no WAYLAND_DISPLAY/DISPLAY is set. Other ttys stay shell (recovery). Not tested by a real login; a graphical greeter (greetd + a GTK4 greeter) is the later option.

## 2026-10-19 14:01 retire-Ubuntu safe tests (see ~/autark-retire-checklist.md)
- /sources/linux-7.1.8/.config == /boot/config-7.1.8 (0 diff lines); utsrelease 7.1.8 = uname -r.
- dracut as tan to scratch: 19,153,978 bytes (real initramfs 19,153,102): the Autark dracut config reproduces.
- ukify: plain build fails: 'Tool sbverify not installed!' (sbsigntools missing). Works with --signtool systemd-sbsign --no-sign-kernel; output signed (PE security table 1448 bytes). Throwaway key shredded. Nothing in /boot, the ESP or /etc/autark was touched.

## 2026-10-19 14:04 staged efivar 39, efibootmgr 18, tpm2-tools 5.8 (for retiring Ubuntu/Windows)
- Downloaded to ~/browser-src/dl (hashes in SHA256SUMS), added as the last three packages of phase8c-inside.sh (after epiphany). Not built yet: the running 8c instance reads the old copy; they get built the next time the script is started (after WebKit/Epiphany). All their library dependencies (tss2-esys/mu/tcti-device, libcurl, openssl, uuid, popt) are present.

## 2026-10-19 14:08 WebKit build interrupted at 140/708
- ninja: build stopped: interrupted by user (SIGINT) at ~13:58. Not from my guard (sudo log shows only pause8c/resume8c at 13:57). Cause unknown. Tree intact, restarted to resume.

## 2026-10-19 14:09 signing config
- /etc/autark/secureboot: db.crt, db.der, db.key only (no PK/KEK). ~/uki.conf.proposed filled with those paths; not installed. Checklist updated with the PK/KEK and PCR-11 caveats.

## 2026-10-19 14:14 TPM binding checked
- cryptsetup luksDump json (as root via ~/pcr-check.sh): systemd-tpm2 token 2, tpm2-pcrs [7], pin true, bank sha256. Kernel updates signed with the same db key keep PCR 7; unlock survives. BIOS/dbx/Secure Boot changes would not.
- /etc/kernel/uki.conf installed (identical to ~/uki.conf.proposed).

## 2026-10-19 14:20 autark-terminal written (not compiled)
- New crate crates/autark-terminal (Cargo.toml, src/{main,window,tab,colors,check}.rs, terminal.css, data/org.autark.Terminal.desktop, data/autark-terminal.svg), one line added to the workspace members in Cargo.toml. Uses vte4 0.10 (vendored in ~/crates-merged, not /sources/crates-8b) and needs VTE 0.84 installed (phase8d, not run yet), so it has only been syntax-checked with rustfmt; type errors against the real bindings are expected and will be fixed when VTE is there.
- Features: tabs, Linen colours (own light/dark 16-colour sets), Geist Mono 12, cwd inheritance, copy/paste, search, zoom, tab switching, new window; Ctrl+Shift+V paste goes through Kith's Check (org.autark.AI1) and asks first when a multi-line paste rates >= 0.6 (middle-click paste is VTE's own and is not checked).
- NOTE: ~/autark-tools is being edited by another session today (about 30 files changed: new crates calc/player/viewer/archive/clock/hw/keys, launcher, shot, notifyd, and autark-ai files I also touched). I only added new files plus one workspace line.

## 2026-10-19 14:28 autark-vault spec written
- ~/autark-vault-spec.md: password manager as a UI over the existing Secret Service (oo7-daemon), no new vault format or crypto. Open questions to answer before coding: whether oo7 stores attributes in the clear, vault collection vs login keyring, clipboard password-manager hint support, TOTP separation, a Kith deny rule. Needs the sha1 crate vendored.
- ~/autark-opensource-checklist.md also written earlier today.

## 2026-10-19 14:30 security follow-ups prepared
- LLMNR/mDNS are on (resolvectl: +LLMNR +mDNS; port 5355 on all interfaces). Proposed ~/llmnr-off.conf (not installed). nft binary and nftables kernel support exist; no ruleset checked (needs root); ~/nftables.proposed drafted (default-deny input; not installed). Port 41467 on localhost: owner not identifiable as tan. Checklist section F (patching) added.

## 2026-10-19 14:34 Bluetooth
- User: no Bluetooth/BLE. Hardware fine: hci0 (Intel 8087:0033, btusb), firmware intel/ibt-0040-0041.sfi loaded, rfkill unblocked, kernel BT/BT_LE/BT_BREDR/BT_INTEL/BT_HCIBTUSB on, BlueZ 5.87 installed (bluetoothd, bluetoothctl). Cause: bluetooth.service disabled and inactive. Fix: systemctl enable --now bluetooth.service (user to run). Correction to the earlier note "bluez not built".

## 2026-10-19 14:35 OpenSSL 4.0.3 + curl 8.23.0 staged (security)
- autark-cve-watch found OpenSSL 4.0.1 (24 CVEs, 14 high/critical; CVE-2026-63073 verified in range 4.0.0 <= v < 4.0.2) and curl 8.21.0 (9, all high/critical; CVE-2026-19931 verified, fixed in 8.22.0).
- Downloaded openssl-4.0.3.tar.gz (sha256 325b5c80...16d9 equal on github, openssl.org and the published .sha256) and curl-8.23.0.tar.xz (sha256 8dadd7d2...e6c5 equal on curl.se and github). Added as the last two packages of phase8c-inside.sh with the build options of the 4.0.1/8.21.0 builds (curl-config --configure; OpenSSL: LFS recipe, openssldir /etc/ssl, zlib on). Runs after the current 8c run; then reboot.

## 2026-10-19 14:36 boot chain CORRECTION
- EFI variables read as tan: Boot0000 Windows Boot Manager, 0001 Autark (\EFI\autark\shimx64.efi), 0002 Ubuntu (\EFI\ubuntu\shimx64.efi), 0003 Autark (previous), 0004 UEFI OS; BootOrder 0002 0000 0001 0003 0004. Firmware db = 4 Microsoft certs only. So Autark's db.key is a MOK-chain key (shim), not a firmware db key; my earlier "missing PK/KEK" alarm was wrong. Checklist corrected.

## 2026-10-19 14:42 WebKitGTK 2.54.1 INSTALLED; Epiphany configure needs itstool; /home full; kernel + libxml2 staged
- WebKitGTK built and installed (pkg-config webkitgtk-6.0 = 2.54.1, web-process-extension too). Took from 12:34 to ~14:37 with the thermal guard (about 20 pauses at 89-95 C).
- Epiphany 51.1: help/meson.build:34 Program 'itstool' not found (gnome.yelp). Same cause as AppStream: itstool needs libxml2's Python bindings. Fix: stub that handles both itstool command forms (-m MO -o DIR files, and -j FILE -o OUT) and copies the English pages.
- /home hit 100% (0 bytes free): the kernel tarball download failed (curl 23). ~/autark-tools/target is 5.1 GB (debug 2.3 GB, release 2.9 GB), not mine. Freed ~500 MB of my own scratch (ff-bin/x, vendor scratch, partial downloads). Large downloads now go to /var/tmp/autark-dl (on /, 21 GB free).
- Staged: libxml2 2.15.4 (CVE-2026-86140) and kernel 7.2.11 (7.1.x is unmaintained): script builds the kernel and modules and an initramfs into /sources/kernel-out/7.2.11 and stops; it never writes /boot or the ESP and never reads /etc/autark/secureboot. Hashes: ~/browser-src/SHA256SUMS-var-tmp.

## 2026-10-19 14:44 Epiphany 51.1 -> 48.5 (blueprint-compiler)
- 51.1: src/meson.build:120 Program 'blueprint-compiler' not found. It has 37 .blp UI files and no pre-built .ui; blueprint-compiler needs PyGObject and GObject-Introspection typelibs (none here: GTK4/libadwaita were built with introspection off). 49.9.1 and 50.6 also use blueprint.
- 48.5 (GNOME 48) uses plain .ui, needs libadwaita >= 1.6 (have 1.9.4) and webkitgtk >= 2.43.4 (have 2.54.1); GNOME-verified sha256. The engine (WebKitGTK 2.54.1) is current; only the Epiphany shell is a year older. Moving to 51 later needs gobject-introspection + PyGObject + blueprint-compiler and rebuilding GTK4/libadwaita with introspection.
- Also: SHA256SUMS had been regenerated with dl/ prefixes and the script's staging check refused to run ("a tarball changed"); regenerated from inside dl/.

## 2026-10-19 14:45 Epiphany 48.5 built; install script needs update-desktop-database
- compile OK; install: "Failed to run install script update-desktop-database: Executable was not found". Cause: desktop-file-utils not installed. Fix: package desktop-file-utils 0.28 (sha256 equals freedesktop's published .sha256sum) before epiphany; it also builds the mimeinfo.cache that lets apps open links. All of Epiphany's files had already been installed by then; the rerun resumes the build tree and only reinstalls.

## 2026-10-19 14:46 Epiphany: stale meson configure
- desktop-file-utils installed, but the Epiphany rerun still failed with "update-desktop-database: Executable was not found": the resumed tree kept meson's configure-time lookup. Fix: rm -rf autark-build in pkg_epiphany so it reconfigures (it is small).

## 2026-10-19 14:49 PHASE 8c DONE: WebKitGTK 2.54.1 + Epiphany 48.5 + efibootmgr + tpm2-tools installed
- Epiphany first showed a blank page; WEBKIT_DISABLE_COMPOSITING_MODE=1 and WEBKIT_DISABLE_DMABUF_RENDERER=1 both fix it (page, padlock/TLS fine). Chose the lighter DMABUF one; exported in ~/.bash_profile (applies at next login). Probable cause: WebKit's DMABuf path built with GBM on and GStreamer GL off (the same combination that needed the source patch).
- Removed crates/autark-terminal from the workspace members in ~/autark-tools/Cargo.toml: the other session reported the workspace no longer built because the crate needs vte4 (not in /sources/crates-8b) and VTE is not installed. Added NOT-IN-WORKSPACE.md in the crate explaining how to enable it.
- Three Claude sessions are working in this machine (this one, "Kith capabilities", "Jev"), sharing ~/autark-tools; one of them deleted target/debug (/home 68% used, 2.7 GB free).
- efibootmgr installed but `efibootmgr` was not found by tan's PATH (check /usr/sbin); tpm2_pcrread is there.
