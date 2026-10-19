# Before publishing Autark: cleanup scan (2026-10-19)

Scan of ~/autark-tools (source), my scripts (~/browser-src, ~/ff-bin, ~/*.sh) and /sources/8b. Values of anything secret were never printed.

## Source tree (~/autark-tools): in good shape

- No private keys, API keys, tokens or passwords committed. The one "password" hit is a UI string about pam_unix prompts.
- Jev (the cloud engine, crates/autark-ai/src/jev.rs) reads its key from the Secret Service keyring or the TYPESAFE_API_KEY environment
  variable, and says it never logs it. Nothing is hard-coded. It talks to api.typesafe.ai, so say so in the README (and that
  local_only = true keeps everything on the laptop).
- `/home/tan` appears only in two unit-test strings (runner.rs, wallpaper.rs); `nvme0n1`/"Cyborg 15 A13UCK" only in tests
  (autark-hw's MSI controls are test fixtures for a hardware profile, which is the right shape). UUIDs in sample.rs are fake test data.
- README links to github.com/Seuketchi/autark (private, 404 to the public) and refers to design artboards in it: fix or publish.

## To fix before the first public commit

1. .cargo/config.toml points cargo at /sources/crates-8b (a local path). It is tracked in my local git only because I created it; keep it
   out (.gitignore it) or document `cargo vendor`. .gitignore has only /target. The target folder is 5.1 GB: never commit.
2. Replace `/home/tan` test paths with `/home/user` (cosmetic).
3. A vendoring story: crates-8b.tar is not in the repo. Say how to build offline (`cargo vendor`) or online.
4. Third-party C in crates/autark-shot/csrc (vpx_shim.c) and the opus/vpx FFI: state the licences (libvpx BSD, opus BSD).
5. The README's apt line and Ubuntu notes: decide if Ubuntu stays a supported dev host.

## My own scripts: personal, not for the public repo as they are

- phase8c/8d-inside.sh, go.sh, guard.sh, pause/stop/resume8c.sh: hard-coded /home/tan, the sudoers rule workflow, the thermal limits of
  this one laptop. The 8c script's *content* is publishable (it is an honest build recipe with [Autark] deviations); move the
  tarball staging (`dl=/home/tan/browser-src/dl`) to a variable and drop the helper scripts.
- ff-bin/install-firefox.sh: hard-coded path and Firefox 158.0 sha256. Fine as a template; better as a script that downloads and
  verifies the current release.
- pcr-check.sh: contains this machine's LUKS UUID. Do not publish.
- fix-sudoers.sh and the sudoers drop-in: user-specific and a security smell. Do not publish.
- ~/8b-report.md is a working log: LUKS/disk UUIDs, hostnames, boot details. Keep private; write a sanitised build log instead.

## Never publish (keys and secrets in or near the project)

- /etc/autark/secureboot/{db.key,db.crt,db.der}: the db signing key lets anyone sign boot images this laptop trusts. Never commit,
  never paste. (PK/KEK are not on this machine: find and protect them.)
- ~/.config/claude-token (login token), ~/.ssh/id_ed25519 (private key), ~/.config/autark/ai.toml (fine, but check for a key
  before sharing), the LUKS recovery passphrase.
- A history check before the first push: run a secret scanner (gitleaks or trufflehog) over the full git history, not just the tree.

## Licences to settle

- autark-tools declares MIT OR Apache-2.0. Say whether the distro scripts and docs share it.
- The distro itself ships GPL software: publish the source or offer for it; Firefox is distributed under Mozilla's terms with its
  trademarks (a script that fetches it is safer than redistributing the binary); the Geist fonts are SIL OFL.
- Names: "Autark", "Kith", "Jev" (Jev's service is typesafe.ai's: use its name correctly), "Galley" (separate private app).

## Hardware layering (what the other session already started)

- hardware/kernel-profile.patch and crates/autark-hw point the right way: machine-specific kernel config and controls as a *profile*,
  everything else generic. Keep going: one profile per supported laptop (this MSI Cyborg 15 A13UCK first), a broad default kernel,
  and an installer that enrols the TPM, Secure Boot keys and disk IDs at install time instead of shipping them.
