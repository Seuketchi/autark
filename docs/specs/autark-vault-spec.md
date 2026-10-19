# autark-vault: Autark's password manager (spec, draft 1, 2026-10-19)

A native GTK4 app over the keyring Autark already has (oo7-daemon, the Secret Service on D-Bus), in the Linen look. It adds no new vault
format and no new cryptography: the keyring encrypts and unlocks (with the login password, through pam_oo7); this app is the
interface, the generator, TOTP, import/export and the safe handling of what it shows.

## 1. Goals

1. See, search, add, edit and delete logins, secure notes and cards in one place.
2. Copy a password or a one-time code without leaving it lying around: the clipboard is cleared, and clipboard history never keeps it.
3. Generate strong passwords and passphrases; show strength.
4. TOTP codes (RFC 6238) next to the login they belong to.
5. Lock when the session locks and after idle; never write secrets to disk, logs, crash dumps or the AI log.
6. Import (Bitwarden JSON, Firefox/Chrome CSV, KeePass CSV) and an encrypted export.
7. Later: browser autofill (Firefox through an extension), Epiphany through libsecret, passkeys.

Non-goals (v1): cloud sync, sharing, a browser extension, passkeys, being a second keyring.

## 2. Threat model

In scope: another process of the same user reading the screen/clipboard; shoulder surfing; a lost or stolen *locked* laptop; a
malicious or buggy clipboard manager; the AI assistant reading things it should not; secrets leaking through logs, swap, core dumps.
Out of scope: malware running as the user *while the keyring is unlocked* (it could call the Secret Service itself; the sandbox
profile for apps is the mitigation, not this app), a compromised kernel, physical attacks on an unlocked, running laptop.
Hard rules: no network access from this app at all (the sandbox profile denies it); Kith/`autark-ai` never reads the vault.

## 3. Architecture

- One crate, `autark-vault` (GTK4 + zbus + zeroize + getrandom + hmac/sha1/sha2). It talks to `org.freedesktop.secrets` directly over
  D-Bus in the "plain" algorithm, like autark-accounts and autark-settings do today (same helper shape; factor it into autark-common).
- Its own collection if oo7 supports it, else the default one under `application = autark-vault`. Decide after reading oo7's file format
  (see open question 1).
- A later helper `autark-vault-host` (native messaging) for Firefox; Epiphany uses libsecret schemas, which this app can read.
- Runs under `autark-sandbox` with: Wayland only, no network, D-Bus limited to the Secret Service and the portal/clipboard.

## 4. Data model

One Secret Service item per entry. Public attributes stay minimal and opaque, so a keyring file that leaks reveals nothing:
`application=autark-vault`, `kind=login|note|card`, `id=<uuid>`. Everything else lives in the *secret payload*, one JSON object
(zeroized after use): title, username, password, urls[], totp{secret, digits, period, algorithm}, notes, tags[], folder, created,
modified, history[] (last 5 passwords, so a bad change can be undone). The item label is the title (the keyring may expose labels:
open question 2). The app loads and decrypts all entries at unlock and searches in memory; a personal vault is hundreds, not millions.

## 5. Features, v1

- **List and search:** two panes (folders/tags | list | detail), fuzzy search over title, username, URL, tags; keyboard first
  (Ctrl+F search, Enter opens, Ctrl+C copies the password, Ctrl+Shift+C username, Ctrl+B opens the URL).
- **Copy:** uses the clipboard with the "password manager" hint so history tools skip it (mime `x-kde-passwordManagerHint=secret`);
  clears after 30 s only if the clipboard still holds our value. The launcher's clipboard history (crates/autark-launcher/src/clipboard.rs)
  must honour the hint: a small change to coordinate with the other session.
- **Generator:** CSPRNG (getrandom) with rejection sampling (no modulo bias); length 8-128, character classes, no-lookalike option; passphrase
  mode from a bundled word list (no network); entropy shown in bits, not stars.
- **TOTP:** RFC 6238 (SHA-1/256/512, 6-8 digits, 30/60 s), countdown ring; `otpauth://` URIs paste in. Needs the `sha1` crate vendored.
- **Reveal:** passwords are dots; Show is held or timed (10 s) and re-hides on blur/lock. No screenshots of the detail pane: the window
  sets the "secure" surface hint where the compositor supports it.
- **Lock:** on `autark-lock` (logind Lock signal), after N idle minutes (default 5), on suspend; locking drops every decrypted value.
- **Health (local only):** reused, weak and old passwords; no breach lookups in v1 (it would need the network).
- **Import/export:** parsers are strict and fuzzed; export is an age-style passphrase-encrypted file via a vetted crate, never plain
  JSON/CSV unless the user explicitly types the confirmation.

## 6. UI

Linen tokens from autark-common (@surface, @sidebar, @accent...), Geist, the same tab-less single window as Files/Notes. Empty state
explains the keyring and links Settings > Password. Destructive actions (delete, overwrite on import) have Undo, not dialogs.

## 7. Tests and review (this is the most security-sensitive app we ship)

- Unit: RFC 6238 test vectors; generator distribution test (chi-square on class counts); JSON round-trip; entry history trimming.
- Integration: a mock Secret Service on a private D-Bus (dbus-daemon in the test) for add/search/update/delete/lock/unlock flows.
- Fuzz the importers and the otpauth parser. `cargo deny` / `cargo audit` on dependencies; keep the dependency list tiny and vendored.
- No `unwrap` on secret paths; no `Debug` on secret types; `zeroize` on drop; mlock where the platform allows; core dumps disabled
  (`prctl(PR_SET_DUMPABLE, 0)`) in this process.
- A written review by a second pair of eyes (the other session, or Tan) before it holds real passwords. Start with a throwaway keyring.

## 8. Open questions (answer before coding)

1. Does the oo7 keyring file hash/encrypt *attributes* or store them in the clear? (Decides how opaque the attributes must be and
   whether labels may hold titles.) Read oo7-0.6's file format source; ask the oo7 daemon in a scratch keyring.
2. A separate "vault" collection with its own passphrase (stronger: logging in no longer unlocks the vault) vs the login keyring
   (simpler: unlocked at login by PAM). Recommend: login keyring for v1, a separate collection as a setting later.
3. Clipboard-hint support: does Wayfire/wl-clipboard path used by foot, GTK4 and the launcher carry the hint? Test with the launcher.
4. TOTP seeds next to passwords weaken the "second factor": offer a separate collection for TOTP (Settings toggle) later.
5. Kith: add an explicit deny so `autark-ai` tools, MCP and Act can never read items with `application=autark-vault`.

## 9. Milestones

M0 (a day): answer the open questions; factor the Secret Service helper into autark-common; skeleton window.
M1: read-only list/search/detail + lock + copy with clearing. M2: add/edit/delete + generator + history.
M3: TOTP + import + health. M4: encrypted export + sandbox profile + security review. M5: Firefox extension + native host.
