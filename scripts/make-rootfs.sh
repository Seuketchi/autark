#!/bin/bash
# make-rootfs.sh: turn a finished Autark system into the release rootfs that autark-install unpacks
# (docs/specs/installer.md). It copies the tree without anything that belongs to one machine or one person (keys,
# users, passwords, saved networks, machine-id, fstab, crypttab, the boot image), checks the copy, and packs it.
#
#   sudo scripts/make-rootfs.sh --src /mnt/autark-ro --version 0.1 [--out DIR] [--sign KEY] [--keep] [--dry-run]
#
# --src is the root of the system to package, mounted somewhere (build-guide step 7 mounts it with open-autark-ro.sh).
# Prefer a system built for release, not a daily-driver one: whatever is installed on it ships. Output, in --out
# (default: the current folder): autark-rootfs-<version>.tar.zst and a SHA256SUMS file; --sign KEY also writes a
# minisign signature next to the tarball. --keep leaves the staging folder for inspection. --dry-run only lists what
# would be left out. The staging copy is as big as the system: set TMPDIR to a folder with room (not the live root).
set -euo pipefail

SRC= VERSION= OUT=. SIGN= KEEP=0 DRY=0
die() { echo "make-rootfs: $*" >&2; exit 1; }
usage() { sed -n '2,/^set -e/p' "$0" | sed '$d;s/^# \{0,1\}//' >&2; exit 2; }
while [ $# -gt 0 ]; do
  case $1 in
    --src) SRC=${2:?}; shift ;;
    --version) VERSION=${2:?}; shift ;;
    --out) OUT=${2:?}; shift ;;
    --sign) SIGN=${2:?}; shift ;;
    --keep) KEEP=1 ;;
    --dry-run|-n) DRY=1 ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
  shift
done
[ -n "$SRC" ] && [ -n "$VERSION" ] || usage
[[ $VERSION =~ ^[0-9A-Za-z._-]+$ ]] || die "version: letters, digits, . _ -"
[ -f "$SRC/etc/os-release" ] && [ -d "$SRC/usr/lib/modules" ] || die "$SRC doesn't look like an Autark root (no etc/os-release or usr/lib/modules)"
grep -qi '^ID=autark' "$SRC/etc/os-release" || die "$SRC/etc/os-release is not Autark's"
[ "$DRY" = 1 ] || [ "$(id -u)" = 0 ] || [ -n "${MAKE_ROOTFS_TEST:-}" ] || die "needs root to read the whole tree (or use --dry-run)"

# Left out entirely, relative to the root. One machine's identity, secrets, or things the installer makes itself.
EXCLUDES=(
  ./proc ./sys ./dev ./run ./tmp ./var/tmp ./mnt ./media ./sources ./lost+found
  ./home ./root                          # people and their files, including /root/kernel-keys and build keys
  ./var/log ./var/cache ./var/lib/iwd ./var/lib/bluetooth ./var/lib/NetworkManager
  ./var/lib/ollama ./var/lib/private ./var/lib/tpm2-tss     # a service's own identity key and models; DynamicUser state; this machine's TPM store
  ./var/lib/systemd/random-seed ./var/lib/systemd/credential.secret ./var/lib/systemd/coredump ./var/lib/systemd/pstore
  ./var/lib/dbus/machine-id ./var/lib/systemd/linger
  ./etc/machine-id ./etc/hostname ./etc/fstab ./etc/crypttab ./etc/kernel/cmdline ./etc/cryptsetup-keys.d
  './etc/ssh/ssh_host_*' ./etc/autark/secureboot ./etc/autark/pkg-secret.key ./etc/autark/*.key
  ./etc/sudoers.d ./etc/resolv.conf ./etc/openvpn ./etc/adjtime
  ./boot/efi ./boot/initramfs-*.img ./boot/*.old
  './root/.*' ./etc/shadow- ./etc/passwd- ./etc/group- ./etc/gshadow-
)

# Files that are rewritten rather than copied: the account databases, to system accounts only.
ACCOUNTS=(etc/passwd etc/group etc/shadow etc/gshadow)

if [ "$DRY" = 1 ]; then
  echo "would leave out of $SRC:"; printf '  %s\n' "${EXCLUDES[@]}"
  echo "would keep only system accounts (UID/GID under 1000, plus nobody/nogroup) in: ${ACCOUNTS[*]}"
  exit 0
fi

STAGE=$(mktemp -d "${TMPDIR:-/var/tmp}/autark-rootfs.XXXXXX")
cleanup() { [ "$KEEP" = 1 ] || rm -rf "$STAGE"; }
trap cleanup EXIT

echo "== copying $SRC to $STAGE (without the machine-specific parts)"
exargs=(); for e in "${EXCLUDES[@]}"; do exargs+=(--exclude="$e"); done
tar -C "$SRC" --one-file-system --numeric-owner --xattrs --acls -cf - "${exargs[@]}" . | tar -C "$STAGE" --numeric-owner --xattrs --acls -xpf -
# The excluded folders themselves come back empty, with the right modes, as mount points and runtime directories.
for d in proc sys dev run tmp var/tmp mnt media home root; do install -d "$STAGE/$d"; done
chmod 1777 "$STAGE/tmp" "$STAGE/var/tmp"; chmod 0700 "$STAGE/root"
install -d -m 0755 "$STAGE/boot/efi" "$STAGE/var/log" "$STAGE/var/cache"

echo "== keeping system accounts only"
awk -F: '$3 < 1000 || $1 == "nobody" { print }' "$SRC/etc/passwd" > "$STAGE/etc/passwd"
awk -F: '$3 < 1000 || $1 == "nogroup" || $1 == "nobody" { print }' "$SRC/etc/group" > "$STAGE/etc/group"
# Every password is locked: the installer sets the new user's, and root stays unreachable by password.
awk -F: -v OFS=: 'NR==FNR { keep[$1] = 1; next } ($1 in keep) { $2 = "!"; print }' "$STAGE/etc/passwd" "$SRC/etc/shadow" > "$STAGE/etc/shadow"
awk -F: -v OFS=: 'NR==FNR { keep[$1] = 1; next } ($1 in keep) { $2 = "!"; $3 = ""; $4 = ""; print $1, $2, "", "" }' "$STAGE/etc/group" "$SRC/etc/gshadow" > "$STAGE/etc/gshadow"
chmod 0644 "$STAGE/etc/passwd" "$STAGE/etc/group"; chmod 0600 "$STAGE/etc/shadow" "$STAGE/etc/gshadow"
# Group members that were removed users are dropped from the member lists.
awk -F: -v OFS=: 'NR==FNR { u[$1] = 1; next } { n = split($4, m, ","); out = ""; for (i = 1; i <= n; i++) if (m[i] in u) out = out (out == "" ? "" : ",") m[i]; $4 = out; print }' "$STAGE/etc/passwd" "$STAGE/etc/group" > "$STAGE/etc/group.new" && mv "$STAGE/etc/group.new" "$STAGE/etc/group"

echo "== checking the copy"
bad=0
if [ -n "$(awk -F: '$3 >= 1000 && $1 != "nobody"' "$STAGE/etc/passwd")" ]; then echo "  ! a user account is left in passwd"; bad=1; fi
if awk -F: '$2 !~ /^[!*]/' "$STAGE/etc/shadow" | grep -q .; then echo "  ! a password hash is left in shadow"; bad=1; fi
for f in etc/machine-id etc/hostname etc/fstab etc/crypttab etc/kernel/cmdline etc/autark/secureboot etc/autark/pkg-secret.key root/kernel-keys; do
  if [ -e "$STAGE/$f" ]; then echo "  ! $f is in the copy"; bad=1; fi
done
if [ -n "$(find "$STAGE/home" "$STAGE/root" -mindepth 1 2> /dev/null | head -1)" ]; then echo "  ! /home or /root is not empty"; bad=1; fi
# Private keys anywhere outside the system's certificate store: a PEM header on a line of its own (docs that only mention one are not keys).
while IFS= read -r f; do echo "  ! private key material: ${f#"$STAGE"}"; bad=1; done < <(
  grep -rIlE --exclude-dir=proc --exclude-dir=sys -e '^-----BEGIN [A-Z ]*PRIVATE KEY-----[[:space:]]*$' "$STAGE/etc" "$STAGE/var" "$STAGE/usr/share" "$STAGE/opt" 2> /dev/null | head -20)
[ "$bad" = 0 ] || die "the copy failed its checks (see above); nothing was packed"
echo "  ok"

echo "== packing"
install -d "$OUT"
TAR=$OUT/autark-rootfs-$VERSION.tar.zst
tar -C "$STAGE" --numeric-owner --xattrs --acls --sort=name -cf - . | zstd -q -T0 -19 -f -o "$TAR"
( cd "$OUT" && sha256sum "$(basename "$TAR")" > SHA256SUMS )
if [ -n "$SIGN" ]; then minisign -S -s "$SIGN" -m "$TAR" || die "signing failed"; fi
ls -l "$TAR" | awk '{printf "== %s: %.1f GiB\n", $9, $5 / 1073741824}'
cat "$OUT/SHA256SUMS"
