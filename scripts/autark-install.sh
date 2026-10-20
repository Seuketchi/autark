#!/bin/bash
# autark-install: put Autark on a blank disk (docs/specs/installer.md). Needs root. Version 1: partition, encrypt,
# unpack the release rootfs, write the machine's own files, build the signed boot image. It leaves out Secure Boot
# enrolment and the TPM, which come after the first boot (see the closing message).
#
#   autark-install --disk /dev/nvme1n1 --rootfs autark-rootfs-1.tar.zst --pubkey autark.pub \
#                  --hostname laptop --user ada [--dry-run]
#
# --dry-run prints every command and changes nothing. Secrets are only ever read from a prompt or from files
# (--passphrase-file, --user-password-file), never from arguments, and live in a 0700 folder on tmpfs until exit.
# --until configure stops after the machine's files are written (before the boot image) and shows them; a test aid.
# --image FILE works on a disk image file instead of a device (for tests: it is attached as a loop device).
set -euo pipefail

DISK= IMAGE= ROOTFS= PUBKEY= HOSTNAME_= USER_= DRY=0 NOVERIFY=0 CONFIRM= PASSFILE= USERPASSFILE= UNTIL=boot
usage() { sed -n '2,/^set -e/p' "$0" | sed '$d;s/^# \{0,1\}//' >&2; exit 2; }
die() { echo "autark-install: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case $1 in
    --disk) DISK=${2:?}; shift ;;
    --image) IMAGE=${2:?}; shift ;;
    --rootfs) ROOTFS=${2:?}; shift ;;
    --pubkey) PUBKEY=${2:?}; shift ;;
    --no-verify) NOVERIFY=1 ;;
    --hostname) HOSTNAME_=${2:?}; shift ;;
    --user) USER_=${2:?}; shift ;;
    --passphrase-file) PASSFILE=${2:?}; shift ;;
    --user-password-file) USERPASSFILE=${2:?}; shift ;;
    --confirm-erase) CONFIRM=${2:?}; shift ;;
    --until) UNTIL=${2:?}; shift ;;
    --dry-run|-n) DRY=1 ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
  shift
done

[ -n "$DISK$IMAGE" ] || usage
case $UNTIL in boot|configure) ;; *) die "--until: boot or configure" ;; esac
[ -z "$DISK" ] || [ -z "$IMAGE" ] || die "give --disk or --image, not both"
[ -n "$ROOTFS" ] && [ -n "$HOSTNAME_" ] && [ -n "$USER_" ] || usage
[[ $HOSTNAME_ =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || die "hostname: lowercase letters, digits and dashes"
[[ $USER_ =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "user name: lowercase letters, digits, - and _"
[ -f "$ROOTFS" ] || die "no such rootfs: $ROOTFS"
if [ "$NOVERIFY" = 0 ]; then
  [ -n "$PUBKEY" ] && [ -f "$PUBKEY" ] || die "--pubkey is required to check the rootfs (or --no-verify for a test)"
  [ -f "$ROOTFS.minisig" ] || die "no $ROOTFS.minisig"
fi
[ "$DRY" = 1 ] || [ "$(id -u)" = 0 ] || die "needs root (try --dry-run to see the plan)"

# Everything that changes the system goes through run, so --dry-run shows it without doing it.
run() { if [ "$DRY" = 1 ]; then printf '  + %s\n' "$*"; else "$@"; fi; }
say() { printf '== %s\n' "$*"; }

SECRETS= LOOP= MNT=/mnt/autark-install
# The installer's own mapper names: the installed system calls its volumes autark and autark-home (fstab, crypttab and the
# kernel command line below), and a machine that already runs Autark has those names taken.
MAPR=autark-install-root MAPH=autark-install-home
cleanup() {
  set +e
  if [ "$DRY" = 0 ]; then
    mountpoint -q "$MNT" && umount -R "$MNT"
    [ -e /dev/mapper/$MAPH ] && cryptsetup close $MAPH
    [ -e /dev/mapper/$MAPR ] && cryptsetup close $MAPR
    [ -z "$LOOP" ] || losetup -d "$LOOP"
  fi
  [ -z "$SECRETS" ] || rm -rf "$SECRETS"
}
trap cleanup EXIT

# --- 1. check -----------------------------------------------------------------------------------------------------
say "checking the machine"
[ -d /sys/firmware/efi ] || echo "  ! not booted in UEFI mode: the install works, but the firmware can't be told about Autark from here"
TPM=0; [ -e /dev/tpmrm0 ] && TPM=1
echo "  TPM 2.0: $([ $TPM = 1 ] && echo present || echo none; )"
for tool in sfdisk cryptsetup mkfs.ext4 mkfs.vfat zstd tar dracut ukify openssl; do
  command -v "$tool" > /dev/null 2>&1 || { [ "$DRY" = 1 ] && echo "  ! $tool not found (needed for a real run)" || die "$tool not found"; }
done

if [ -n "$IMAGE" ]; then
  [ -f "$IMAGE" ] || die "no such image: $IMAGE"
  SIZE=$(stat -c %s "$IMAGE"); TARGET=$IMAGE
else
  [ -b "$DISK" ] || { [ "$DRY" = 1 ] && [ -e "$DISK" ] || die "$DISK is not a block device"; }
  SIZE=$(blockdev --getsize64 "$DISK" 2>/dev/null || echo 0); TARGET=$DISK
fi
MIB=$((SIZE / 1048576))
[ "$MIB" -ge 32768 ] || die "$TARGET is $((MIB / 1024)) GiB; Autark needs at least 32 GiB"

# Layout: 1 GiB ESP, root 40% of the rest clamped to 16..64 GiB, /home the remainder.
ESP=1024
ROOT=$(( (MIB - ESP) * 40 / 100 )); [ $ROOT -ge 16384 ] || ROOT=16384; [ $ROOT -le 65536 ] || ROOT=65536
HOME_=$((MIB - ESP - ROOT - 2))
[ "$HOME_" -ge 4096 ] || die "not enough room for /home on $TARGET"

# --- 2. plan and confirm ------------------------------------------------------------------------------------------
if [ "$DRY" = 0 ] && [ -z "$IMAGE" ]; then
  # a blank disk only: nothing mounted from it, and (without --confirm-erase) no signatures at all
  if lsblk -nrpo MOUNTPOINTS "$DISK" | grep -q .; then die "something on $DISK is mounted: that is the running system or the installer medium"; fi
  if [ -n "$(wipefs -n "$DISK" 2>/dev/null)" ] || lsblk -nrpo NAME "$DISK" | sed 1d | grep -q .; then
    echo "$DISK is not blank:"; lsblk -o NAME,SIZE,FSTYPE,LABEL "$DISK"
    [ -n "$CONFIRM" ] || echo "Type its name to erase it, or stop here."
  fi
fi
say "plan for $TARGET ($((MIB / 1024)) GiB)"
echo "  1  ESP    $ESP MiB   FAT32  /boot/efi"
echo "  2  root   $ROOT MiB  LUKS2 + ext4  /"
echo "  3  home   $HOME_ MiB LUKS2 + ext4  /home (unlocked by a key file on the root)"
echo "  rootfs $ROOTFS, host $HOSTNAME_, user $USER_, TPM: $([ $TPM = 1 ] && echo "later (after Secure Boot)" || echo none)"
if [ "$DRY" = 0 ]; then
  want=$(basename "$TARGET")
  if [ -z "$CONFIRM" ]; then
    [ -t 0 ] || die "not a terminal: pass --confirm-erase $want to erase $TARGET"
    read -r -p "Everything on $TARGET will be erased. Type '$want' to go on: " CONFIRM
  fi
  [ "$CONFIRM" = "$want" ] || die "not confirmed; nothing was changed"
fi

# --- secrets ------------------------------------------------------------------------------------------------------
if [ "$DRY" = 0 ]; then
  SECRETS=$(mktemp -d /run/autark-install.XXXXXX); chmod 0700 "$SECRETS"
  askpw() { # askpw FILE PROMPT [SOURCE-FILE]
    if [ -n "${3:-}" ]; then
      [ "$(stat -c %a "$3")" = 600 ] || die "$3 must be mode 600"
      cp "$3" "$1"
    else
      local a b
      read -rs -p "$2: " a; echo; read -rs -p "again: " b; echo
      [ "$a" = "$b" ] && [ -n "$a" ] || die "the two entries differ, or are empty"
      printf %s "$a" > "$1"
    fi
    chmod 0600 "$1"
  }
  askpw "$SECRETS/disk" "Disk passphrase" "$PASSFILE"
  askpw "$SECRETS/user" "Password for $USER_" "$USERPASSFILE"
fi

# --- 3. partition and format ----------------------------------------------------------------------------------------
if [ -n "$IMAGE" ]; then
  say "attaching $IMAGE"
  if [ "$DRY" = 1 ]; then echo "  + losetup --find --show --partscan $IMAGE"; DEV=/dev/loopN
  else LOOP=$(losetup --find --show --partscan "$IMAGE"); DEV=$LOOP; fi
else
  DEV=$DISK
fi
part() { # part N: the device of partition N (nvme0n1p1, sda1, loop0p1)
  case $DEV in *[0-9]) echo "${DEV}p$1" ;; *) echo "$DEV$1" ;; esac
}
P1=$(part 1) P2=$(part 2) P3=$(part 3)

say "partitioning $DEV"
if [ "$DRY" = 1 ]; then
  echo "  + sfdisk $DEV <<< 'label: gpt; ${ESP}MiB ESP; ${ROOT}MiB root; ${HOME_}MiB home'"
else
  wipefs -a "$DEV" > /dev/null
  sfdisk -q "$DEV" << EOF
label: gpt
size=${ESP}MiB, type=U, name=ESP
size=${ROOT}MiB, type=L, name=autark-root
size=${HOME_}MiB, type=L, name=autark-home
EOF
  udevadm settle; partprobe "$DEV" 2> /dev/null || true; udevadm settle
fi

say "formatting"
run mkfs.vfat -F 32 -n ESP "$P1"
DISKKEY=${SECRETS:+$SECRETS/disk}; DISKKEY=${DISKKEY:-<passphrase file>}
run cryptsetup luksFormat --type luks2 --batch-mode --key-file "$DISKKEY" "$P2"
run cryptsetup open --key-file "$DISKKEY" "$P2" "$MAPR"
run mkfs.ext4 -q -L autark /dev/mapper/$MAPR
HOMEKEY=$MNT/etc/cryptsetup-keys.d/autark-home.key
run mkdir -p "$MNT"
run mount /dev/mapper/$MAPR "$MNT"
run install -d -m 0700 "$MNT/etc/cryptsetup-keys.d"
run dd if=/dev/urandom of="$HOMEKEY" bs=64 count=1 status=none
run chmod 0400 "$HOMEKEY"
run cryptsetup luksFormat --type luks2 --batch-mode --key-file "$HOMEKEY" "$P3"
run cryptsetup open --key-file "$HOMEKEY" "$P3" "$MAPH"
run mkfs.ext4 -q -L autark-home /dev/mapper/$MAPH

# --- 4. unpack ------------------------------------------------------------------------------------------------------
say "checking and unpacking $(basename "$ROOTFS")"
if [ "$NOVERIFY" = 1 ]; then echo "  ! --no-verify: the rootfs signature is NOT checked"
else run minisign -V -p "$PUBKEY" -m "$ROOTFS"; fi
if [ "$DRY" = 1 ]; then
  echo "  + zstd -dc $ROOTFS | tar -x -C $MNT --numeric-owner --xattrs --acls -p"
else
  zstd -dc "$ROOTFS" | tar -x -C "$MNT" --numeric-owner --xattrs --acls -p
fi
run mkdir -p "$MNT/home" "$MNT/boot/efi"
run mount /dev/mapper/$MAPH "$MNT/home"
run mount "$P1" "$MNT/boot/efi"

# --- 5. the machine's own files -------------------------------------------------------------------------------------
say "writing this machine's files"
if [ "$DRY" = 1 ]; then
  ROOTUUID='<root LUKS uuid>' HOMEUUID='<home LUKS uuid>' ESPUUID='<ESP uuid>'
else
  ROOTUUID=$(cryptsetup luksUUID "$P2") HOMEUUID=$(cryptsetup luksUUID "$P3") ESPUUID=$(blkid -s UUID -o value "$P1")
fi
write() { # write FILE: stdin becomes MNT/FILE
  if [ "$DRY" = 1 ]; then echo "  + write $1"; cat > /dev/null; else cat > "$MNT/$1"; fi
}
write etc/fstab << EOF
/dev/mapper/autark       /          ext4  defaults       1 1
/dev/mapper/autark-home  /home      ext4  defaults       0 2
UUID=$ESPUUID            /boot/efi  vfat  umask=0077     0 2
EOF
write etc/crypttab << EOF
autark-home  UUID=$HOMEUUID  /etc/cryptsetup-keys.d/autark-home.key  luks
EOF
write etc/hostname <<< "$HOSTNAME_"
run mkdir -p "$MNT/etc/kernel"
# tpm2-device=auto is added once a TPM key is enrolled (after the first boot); until then it is a passphrase prompt
write etc/kernel/cmdline << EOF
rd.luks.name=$ROOTUUID=autark root=/dev/mapper/autark rw
EOF
run rm -f "$MNT/etc/machine-id"
run systemd-machine-id-setup --root="$MNT"
if [ "$DRY" = 1 ]; then
  echo "  + useradd --root $MNT -m -s /bin/bash $USER_   (and chpasswd from the password file)"
else
  grep -q '^wheel:' "$MNT/etc/group" && groups=(-G wheel) || groups=()
  useradd --root "$MNT" -m -s /bin/bash "${groups[@]}" "$USER_"
  printf '%s:%s\n' "$USER_" "$(cat "$SECRETS/user")" | chpasswd --root "$MNT"
fi

if [ "$UNTIL" = configure ]; then
  say "stopping before the boot image (--until configure); what was written:"
  if [ "$DRY" = 0 ]; then
    lsblk -f "$DEV"
    for f in etc/fstab etc/crypttab etc/hostname etc/kernel/cmdline; do echo "--- $f"; cat "$MNT/$f"; done
    echo "--- $USER_ in etc/passwd"; grep "^$USER_:" "$MNT/etc/passwd"
    echo "--- machine-id: $(wc -c < "$MNT/etc/machine-id") bytes; home key: $(stat -c '%a %s bytes' "$HOMEKEY")"
  fi
  exit 0
fi

# --- 6. boot image --------------------------------------------------------------------------------------------------
say "building the signed boot image"
if [ "$DRY" = 0 ]; then
  for d in dev proc sys run; do mount --rbind "/$d" "$MNT/$d"; mount --make-rslave "$MNT/$d"; done
fi
inchroot() { if [ "$DRY" = 1 ]; then printf '  + (in the new system) %s\n' "$*"; else chroot "$MNT" /bin/bash -c "$*"; fi; }
SB=/etc/autark/secureboot
inchroot "install -d -m 0700 $SB && [ -s $SB/db.key ] || openssl req -new -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 -subj '/CN=Autark Secure Boot db/' -keyout $SB/db.key -out $SB/db.crt; chmod 0400 $SB/db.key; openssl x509 -in $SB/db.crt -outform DER -out $SB/db.der"
inchroot 'KVER=$(ls /usr/lib/modules | sort -V | tail -1); dracut --force --kver $KVER /boot/initramfs-$KVER.img'
inchroot 'KVER=$(ls /usr/lib/modules | sort -V | tail -1); mkdir -p /boot/efi/EFI/Linux /boot/efi/EFI/BOOT /boot/efi/EFI/autark; ukify build --linux=/boot/vmlinuz-$KVER-autark --initrd=/boot/microcode.img --initrd=/boot/initramfs-$KVER.img --cmdline=@/etc/kernel/cmdline --os-release=@/etc/os-release --uname=$KVER --signtool=systemd-sbsign --no-sign-kernel --secureboot-private-key=/etc/autark/secureboot/db.key --secureboot-certificate=/etc/autark/secureboot/db.crt --output=/boot/efi/EFI/Linux/autark.efi'
inchroot 'cp /boot/efi/EFI/Linux/autark.efi /boot/efi/EFI/BOOT/BOOTX64.EFI; cp /etc/autark/secureboot/db.der /boot/efi/EFI/autark/autark-db.der'
if [ -d /sys/firmware/efi ] && command -v efibootmgr > /dev/null 2>&1 && [ -z "$IMAGE" ]; then
  run efibootmgr --create --disk "$DEV" --part 1 --label Autark --loader '\EFI\Linux\autark.efi'
fi

say "done"
cat << EOF
Autark is on $TARGET. Before the first boot:
  - Secure Boot: enrol /EFI/autark/autark-db.der from the ESP in the firmware's setup screen (db), then turn Secure
    Boot on. Automatic enrolment is not in this version.
  - TPM: after that first boot, bind the disk to it with  systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 \\
    --tpm2-with-pin=yes --recovery-key /dev/disk/by-uuid/$ROOTUUID  (write the recovery key down), then add
    tpm2-device=auto to /etc/kernel/cmdline and rebuild the boot image.
EOF
