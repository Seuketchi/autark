# Ready to retire Ubuntu and Windows? (checklist)

Written 2026-10-19 from what Autark itself can see (read-only). Status: DONE = verified here, TODO = not yet, UNKNOWN = needs a
look at something only root can read. Nothing below touches /boot, the ESP, LUKS, crypttab, fstab or the Secure Boot keys unless
a step says so, and those steps are for Tan to run as root.

## What Autark already has

- Kernel 7.1.8 source tree built in place (/sources/linux-7.1.8 with .config and vmlinux); config copy at /boot/config-7.1.8.
- systemd's boot-chain tools: ukify, systemd-sbsign, systemd-measure, bootctl, systemd-cryptenroll, kernel-install hooks
  (/usr/lib/kernel/install.d/60-ukify.install, 90-uki-copy.install), /usr/lib/kernel/uki.conf, /etc/kernel/cmdline,
  dracut with /etc/dracut.conf.d/autark.conf, Python pefile, openssl, cryptsetup 2.8.7.
- Secure Boot is on (SecureBoot variable = 1). TPM 2.0 present (/sys/class/tpm/tpm0).
- Signing key material lives in /etc/autark/secureboot (root only; never read or copied by Claude).

## What is missing for self-maintenance

- efibootmgr (manage UEFI boot entries), tpm2-tools (tpm2_pcrread etc., for diagnosing TPM unlock), sbsigntools or efitools
  (only if systemd-sbsign is not enough), a CJK font, an NVIDIA driver, MSI fan/thermal control.

## A. Autark can rebuild and boot itself

1. [PARTLY DONE] The kernel tree's .config is byte-identical (0 differences) to /boot/config-7.1.8 and utsrelease is 7.1.8, so the tree is
   exactly the running kernel. Still TODO: an actual compile into a scratch O= directory (heavy, waits until the browser build is done).
2. [DONE 2026-10-19] Test initramfs built with dracut as the normal user into a scratch folder (19.15 MB; the real one is 19.15 MB). It carries
   the TPM libraries and the systemd cryptsetup token plugin, as /etc/dracut.conf.d/autark.conf intends.
3. [DONE with a catch, 2026-10-19] UKI built and signed with a throwaway key (signature table present, sections .linux/.initrd/.cmdline/...).
   CATCH: plain `ukify build` fails because it needs `sbverify` (sbsigntools), which Autark lacks. It works with
   `--signtool systemd-sbsign --no-sign-kernel`. So kernel-install/ukify on Autark needs either sbsigntools installed or
   SecureBootSigningTool=systemd-sbsign and SignKernel=no in /usr/lib/kernel/uki.conf (or /etc/kernel/uki.conf).
4. [UNKNOWN] Who signs the real UKI today and where does the real key get used? Needs `su` to read /etc/autark/secureboot's layout
   (names only); the answer decides whether a kernel update can be done from Autark alone.
5. [TODO] Do one real kernel update from Autark with Ubuntu still installed as the fallback, and boot it. Only then is A done.
6. [TODO] Install efibootmgr (and tpm2-tools) so boot entries and TPM state can be managed and diagnosed from Autark.

## B. Recovery without another OS

7. [TODO] A rescue path that does not need Ubuntu: a second boot entry with the previous kernel, kept after every update.
8. [TODO] A USB rescue stick (a small Autark rescue image, or any live Linux) tested to open the LUKS volume with the recovery passphrase.
9. [TODO] LUKS recovery passphrase written down and stored off the laptop. (TPM+PIN breaks if firmware or Secure Boot state changes.)
10. [TODO] Secure Boot keys and the PK/KEK/db enrolment material backed up off the laptop, encrypted.
11. [TODO] Test the TPM re-enrol procedure once (systemd-cryptenroll --wipe-slot=tpm2 then --tpm2-device=auto --tpm2-with-pin=yes)
    on a spare keyslot, with Ubuntu still around.

## C. Backups

12. [TODO] /home backed up to an external drive or another machine; restore tested.
13. [TODO] A copy of the distro's build state: phase scripts, /sources hashes, ~/browser-src, ~/autark-tools patches, ~/8b-report.md.

## D. Things only the other systems do today

14. [TODO] MSI firmware / BIOS / EC updates: usually need Windows or MSI's own tools. Decide: do the last update before wiping Windows.
15. [TODO] Fan and thermal control: this laptop reaches 90+ C under load; MSI Center (Windows) sets fan profiles. On Linux look at the
    msi-ec driver / manual fan control; without it heavy builds need the thermal guard.
16. [TODO] NVIDIA RTX GPU: no driver on Autark, so the dGPU is idle (games, GPU compute, video encode, external displays on some
    ports). Decide: add the open kernel modules + userspace, or accept iGPU only.
17. [TODO] Apps and files that only exist on Ubuntu/Windows (Office, games, anything licensed): list them, move or replace each.
18. [TODO] Windows: BitLocker/licence key, anything needing a Windows licence later. Back up the licence key before deleting.

## E. Disk layout (decide before deleting anything)

19. [UNKNOWN] Which partitions are Ubuntu, Windows, shared ESP, recovery? (`lsblk -f` and `efibootmgr -v` as root.) Autark's boot
    partition is /dev/nvme0n1p6; other systems' boot files may live on the same ESP.
20. [TODO] A written plan to reclaim the space (or not), with the order: back up -> remove boot entries last -> resize/delete data
    partitions -> re-test boot. Deleting partitions is hard to undo.

## When to retire which

- Ubuntu: when A and B and C are all DONE.
- Windows: when D (firmware updates, licence key, fan control decision) and C are DONE.

## Findings from reading the install hooks (2026-10-19)
- /etc/kernel/install.d is empty and there is no /etc/kernel/uki.conf: Autark has only the stock systemd kernel-install pipeline.
  The real, signed UKI was therefore built some other way (probably the stage scripts on Ubuntu). To update the kernel from Autark,
  /etc/kernel/uki.conf must name the signing tool (done in ~/uki.conf.proposed) and the real key/certificate paths (UNKNOWN: need
  the file names, only the names, in /etc/autark/secureboot).

## Findings from the key folder listing (2026-10-19, names only)
- /etc/autark/secureboot holds exactly db.crt (1115 B), db.der (782 B) and db.key (1704 B, mode 0400): the Secure Boot "db"
  signing pair, with the DER copy for enrolling. There is NO PK or KEK key on this machine. Consequence: Autark can sign images with
  db.key, but it cannot change which keys the firmware trusts (that needs the KEK/PK, wherever those were kept, probably Ubuntu or
  a USB stick). Item 10 now matters more: find and back up the PK/KEK (and db.key) before Ubuntu is removed.
- ~/uki.conf.proposed now names db.key and db.crt. Install: su -c 'install -m644 -o root -g root /home/tan/uki.conf.proposed /etc/kernel/uki.conf'
- NEW RISK to check first: if the TPM2+PIN LUKS enrolment is bound to PCR 11 (the measured UKI) and not only to PCR 7 (Secure Boot
  state), then ANY new kernel/UKI changes PCR 11 and the TPM will refuse to unlock until re-enrolled (the PIN/recovery passphrase
  still works). Find out which PCRs the keyslot uses before the first real kernel update.

## PCR check result (2026-10-19)
- LUKS TPM2 keyslot (token 2): tpm2-pcrs = [7], no signed-PCR policy, PIN required, sha256 bank.
- So the unlock is bound to PCR 7 (Secure Boot state: the keys and the certificate images were verified against), NOT to PCR 11
  (the measured UKI). A new kernel/UKI signed with the same db key does not change PCR 7, so a kernel update will not break the
  TPM unlock. DONE: the risk above is cleared for kernel updates.
- What WOULD break the TPM unlock (re-enrol, or use the PIN's recovery passphrase): changing the Secure Boot keys or db, a firmware
  update that changes dbx/PK/KEK or resets Secure Boot, clearing the TPM, or toggling Secure Boot. This makes item 14 (MSI BIOS/EC
  updates) a re-enrol event: have the recovery passphrase to hand before any firmware update.

## F. Staying patched without Ubuntu (the biggest security gap, added 2026-10-19)

Ubuntu patches CVEs for you within days. Autark does not: every package is a source tarball you compiled. Before retiring Ubuntu:

21. [TODO] A CVE watch for what faces the network or runs untrusted data: linux kernel (7.1.8), OpenSSL (4.0.1), OpenSSH (10.5p1), curl (8.21.0),
    systemd (261), glibc, libxml2, WebKitGTK/Epiphany (2.54.1), the Firefox binary (158.0), ffmpeg (8.1.3), gnutls (3.8.13), sqlite. Source: each
    project's security page or an RSS feed; a script that lists installed versions from /sources and /var/lib/autark/files and compares.
22. [TODO] A monthly rebuild routine through autark-pkg: fetch new source, verify its hash/signature, rebuild, update the file list, reboot if
    the kernel changed (see section A for the signing path).
23. [TODO] Firefox is a prebuilt binary in a root-owned /opt/firefox: it cannot update itself. Releases come about every 4 weeks, with security
    fixes: re-run ff-bin/install-firefox.sh with the new version and hash (better: a script that fetches the current release and checks
    it against Mozilla's published SHA256SUMS).
24. [TODO] Firewall: nft and the nftables kernel options are present, but whether a ruleset is loaded needs `su -c 'nft list ruleset'`.
    ~/nftables.proposed is a default-deny inbound ruleset (closes SSH from the network unless you uncomment the subnet line).
25. [TODO] LLMNR and mDNS are on (listening on 5355 on all interfaces). ~/llmnr-off.conf turns them off for systemd-resolved.
26. [TODO] SSH: key-only and no root login (good), but it listens on all interfaces. Decide whether you need it at all; if not, disable sshd.socket.
27. [TODO] Remove /etc/sudoers.d/8c-build when the browser build is done; delete the helper scripts from ~/browser-src afterwards.

## CORRECTION and boot-chain facts (read from the UEFI variables, 2026-10-19; replaces earlier assumptions)

- I earlier assumed Autark's db.key was enrolled in the firmware's Secure Boot db, and that the missing PK/KEK needed finding and backing up.
  WRONG. The firmware db holds only four Microsoft certificates (Windows Production PCA 2011, UEFI CA 2011, Windows UEFI CA 2023,
  UEFI CA 2023). Autark boots through shim (\EFI\autark\shimx64.efi, Microsoft-signed), which checks the next stage against the
  MOK list, where Tan's key (db.der) is enrolled. So: firmware db (Microsoft) -> shim -> MOK (Autark key) -> UKI/kernel.
- Consequences: there is no PK/KEK/db of Tan's to back up (item 10 drops to: back up db.key itself, and know how the MOK was enrolled).
  The firmware keys are the laptop maker's and Microsoft's.
- Firmware boot entries: 0000 Windows Boot Manager, 0001 Autark, 0002 Ubuntu, 0003 Autark (previous), 0004 UEFI OS (fallback).
  BootOrder is 0002 0000 0001 0003 0004: Ubuntu first, Autark third. So "Autark (previous)" already is a fallback kernel entry (item 7 is
  partly DONE), and GRUB (Ubuntu's menu that lists Ubuntu and Windows) is not what boots Autark.
- Retiring Ubuntu: Autark and Windows each have their own firmware entries, so neither needs Ubuntu's GRUB. Before deleting Ubuntu:
  set BootOrder so Autark is first (needs efibootmgr, queued in the build) and keep the Windows entry; then remove the Ubuntu entry and
  its \EFI\ubuntu folder. Do not delete \EFI\autark, \EFI\autark-prev or \EFI\Microsoft.
- TPM unlock: still bound to PCR 7. With shim, PCR 7 reflects the Microsoft db and SecureBoot state, not MOK, so kernels signed with the
  same MOK key keep unlocking. What changes PCR 7: a dbx update (Windows Update/fwupd/BIOS can push these), clearing Secure Boot keys,
  toggling Secure Boot. Keep the recovery passphrase handy; retiring Windows removes one source of dbx updates.
- UNKNOWN (needs root to read the ESP): what shim loads next in \EFI\autark (systemd-boot renamed to grubx64.efi, or a UKI), and whether the
  MOK is enrolled with mokutil (not installed). Needed to understand how a new kernel is activated: `su -c 'ls -R /boot/efi/EFI/autark'`.
