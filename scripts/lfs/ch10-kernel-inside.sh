#!/bin/bash
# Build guide Step 6.2: Autark's kernel, trimmed to the target laptop. Runs INSIDE the chroot as root, started
# by ch7-chroot.sh with INSIDE=ch10-kernel-inside.sh. The host copies hardware/target/{kernel.config,lsmod.txt}
# into $LFS/sources as target-kernel.config and target-lsmod.txt first.
#
# Order: Ubuntu's config for this laptop → only the modules it loads (localmodconfig) → the required options
# below → olddefconfig → every required option checked in the final .config (the build stops on a mismatch,
# because olddefconfig silently drops an option whose dependencies aren't met).
set -euo pipefail

if [ ! -e /sources/wget-list-systemd ] || grep -qi ubuntu /etc/os-release 2>/dev/null; then
  echo "ch10-kernel-inside.sh: not inside the Autark chroot; refusing to run" >&2
  exit 1
fi

KVER=7.1.8
SRC=/sources/linux-$KVER
LOG=/sources/logs/kernel.log
mkdir -p /sources/logs

# Required options: "y" built in, "m" module, "n" off, or a quoted string. Grouped by why they're needed.
read -r -d '' REQUIRED << "EOF" || true
# LFS 10.3: options systemd and the book require
WERROR n
PSI y
PSI_DEFAULT_DISABLED n
IKHEADERS n
CGROUPS y
MEMCG y
CGROUP_SCHED y
RT_GROUP_SCHED n
RELOCATABLE y
RANDOMIZE_BASE y
STACKPROTECTOR y
STACKPROTECTOR_STRONG y
NET y
INET y
IPV6 y
UEVENT_HELPER n
DEVTMPFS y
DEVTMPFS_MOUNT y
FW_LOADER_USER_HELPER n
DMIID y
SYSFB_SIMPLEFB y
LEGACY_TIOCSTI n
DRM y
DRM_PANIC y
DRM_FBDEV_EMULATION y
DRM_SIMPLEDRM y
FRAMEBUFFER_CONSOLE y
INOTIFY_USER y
TMPFS y
TMPFS_POSIX_ACL y
X86_X2APIC y
PCI y
PCI_MSI y
IOMMU_SUPPORT y
IRQ_REMAP y
EFI y
EFI_STUB y
PARTITION_ADVANCED y
EFI_PARTITION y
VFAT_FS y
EFIVAR_FS y
NLS_CODEPAGE_437 y
NLS_ISO8859_1 y
NLS_UTF8 y

# Unlock path, built in (build guide 6.2): the disk sits behind Intel VMD (hardware/target/lspci.txt)
VMD y
BLK_DEV_NVME y
BLK_DEV_DM y
DM_CRYPT y
CRYPTO_AES y
CRYPTO_AES_NI_INTEL y
CRYPTO_XTS y
CRYPTO_SHA256 y
CRYPTO_USER_API_SKCIPHER y
EXT4_FS y
TCG_TPM y
TCG_TIS y
TCG_CRB y

# zram swap with zstd (build guide 6.4)
ZRAM y
CRYPTO_ZSTD y
ZRAM_DEF_COMP_ZSTD y

# Hardening (decisions.md "Kernel hardening")
SECURITY_LOCKDOWN_LSM y
SECURITY_LOCKDOWN_LSM_EARLY y
LOCK_DOWN_KERNEL_FORCE_INTEGRITY y
MODULE_SIG y
MODULE_SIG_FORCE y
MODULE_SIG_ALL y
MODULE_SIG_SHA512 y
INIT_ON_ALLOC_DEFAULT_ON y
SLAB_FREELIST_HARDENED y
SLAB_FREELIST_RANDOM y
SHUFFLE_PAGE_ALLOCATOR y
KEXEC n
KEXEC_FILE n
# KEXEC_HANDOVER (live update) selects KEXEC_FILE, overriding the line above; crash dumps need kexec too
KEXEC_HANDOVER n
CRASH_DUMP n
SECURITY_LANDLOCK y
SECURITY_YAMA y
SECURITY_APPARMOR n
SECURITY_SELINUX n

# Ubuntu-specific settings that break this build or aren't Autark's
SYSTEM_TRUSTED_KEYS ""
SYSTEM_REVOCATION_KEYS ""
DEBUG_INFO_BTF n
RUST n
# gendwarfksyms (module symbol versions from DWARF) needs libdw's dwarf.h, which LFS doesn't install;
# genksyms is used instead. No kernel debug info at all: smaller and faster to build.
GENDWARFKSYMS n
# DEBUG_INFO_NONE is one member of a choice; the other members must be turned off for it to win
DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT n
DEBUG_INFO_DWARF4 n
DEBUG_INFO_DWARF5 n
DEBUG_INFO_NONE y

# Firewall (decisions.md: nftables, block all incoming). localmodconfig kept nf_tables but dropped conntrack
# matching (Ubuntu's rules at capture time didn't use it); without NFT_CT, "allow replies" is impossible.
NF_TABLES m
NF_TABLES_INET y
NF_CONNTRACK m
NFT_CT m
NFT_REJECT m
NFT_REJECT_INET m
NFT_LIMIT m
NFT_LOG m

# Phase 8a, Wi-Fi with iwd: it does its crypto through the kernel (AF_ALG and the keyring). Set from the iwd
# documentation as remembered, not fetched: iwd logs any missing algorithm at start, so check that on first Wi-Fi use.
KEYS y
KEY_DH_OPERATIONS y
ASYMMETRIC_KEY_TYPE y
ASYMMETRIC_PUBLIC_KEY_SUBTYPE y
X509_CERTIFICATE_PARSER y
PKCS7_MESSAGE_PARSER y
PKCS8_PRIVATE_KEY_PARSER y
CRYPTO_USER_API_HASH y
CRYPTO_USER_API_AEAD y
CRYPTO_HMAC y
CRYPTO_CMAC y
CRYPTO_MD4 y
CRYPTO_MD5 y
CRYPTO_SHA1 y
CRYPTO_SHA512 y
CRYPTO_ECB y
CRYPTO_CBC y
CRYPTO_DES y
CRYPTO_CCM y
# Wireless regulatory database (wireless-regdb): signed regulatory.db, checked against the kernel's built-in key
CFG80211_REQUIRE_SIGNED_REGDB y
CFG80211_USE_KERNEL_REGDB_KEYS y
RFKILL y

# Phase 8a, Bluetooth (BlueZ, from its BLFS page)
BT_BREDR y
BT_RFCOMM m
BT_RFCOMM_TTY y
BT_BNEP m
BT_BNEP_MC_FILTER y
BT_BNEP_PROTO_FILTER y
BT_HIDP m
CRYPTO_USER m

# Phase 8a, desktop input and graphics (libinput reads evdev; vgem lets llvmpipe work in qemu)
INPUT_EVDEV y
DRM_VGEM m

# qemu test boot (build guide 7a): serial console; the screen comes from SIMPLEDRM above
SERIAL_8250 y
SERIAL_8250_CONSOLE y

# Baseline drivers as modules (build guide 6.2), so devices plugged in later still work
USB_STORAGE m
USB_UAS m
USB_HID m
HID_GENERIC m
HID_MULTITOUCH m
# localmodconfig turns off whole menus this laptop didn't use; their children need the menu back on
USB_NET_DRIVERS m
USB_USBNET m
USB_NET_CDCETHER m
USB_RTL8152 m
USB_ACM m
MEDIA_SUPPORT m
MEDIA_USB_SUPPORT y
USB_VIDEO_CLASS m
SND_USB_AUDIO m
# Raptor Lake audio (8086:51ca) is in the Alder Lake SOF family. This option makes no module of its own (it extends
# the Tiger Lake driver), so localmodconfig dropped it; without it dspcfg falls back to plain HDA and the digital
# mics are lost (first real boot, log.md).
SND_SOC_SOF_ALDERLAKE m
BT_HCIBTUSB m
TYPEC m
TYPEC_UCSI m
UCSI_ACPI m
USB4 m
EXFAT_FS m
NTFS3_FS m
ISO9660_FS m
UDF_FS m
FUSE_FS m
EOF

apply() {
  local sym val
  while read -r sym val; do
    [ -z "$sym" ] || [ "${sym:0:1}" = "#" ] && continue
    case $val in
      y) scripts/config --enable "$sym" ;;
      m) scripts/config --module "$sym" ;;
      n) scripts/config --disable "$sym" ;;
      \"*) scripts/config --set-str "$sym" "${val//\"/}" ;;
    esac
  done <<< "$REQUIRED"
}

check() {
  local sym val got bad=0
  while read -r sym val; do
    [ -z "$sym" ] || [ "${sym:0:1}" = "#" ] && continue
    got=$(grep -E "^(CONFIG_$sym=|# CONFIG_$sym is not set)" .config | head -1 || true)  # no match = unset
    case $val in
      n) [[ -z $got || $got == "# CONFIG_$sym is not set" ]] ;;
      \"*) [[ $got == "CONFIG_$sym=$val" ]] ;;
      *) [[ $got == "CONFIG_$sym=$val" ]] ;;
    esac || { echo "MISMATCH: $sym wanted $val, got '${got:-unset}'"; bad=1; }
  done <<< "$REQUIRED"
  return $bad
}

# A plain subshell, not `{ } || …`: errexit is ignored inside any || / && / if condition.
set +e
(
  set -e
  cd /sources
  rm -rf "$SRC"
  tar -xf linux-$KVER.tar.xz
  cd "$SRC"
  make mrproper
  cp /sources/target-kernel.config .config
  make olddefconfig
  # `yes` answers NEW-option prompts with the default. It dies of SIGPIPE when make exits, which pipefail
  # would count as a failure, so its own status is ignored; make's still counts.
  (yes '' || true) | make LSMOD=/sources/target-lsmod.txt localmodconfig
  # Twice: enabling an option can reveal dependent options that a second pass then sets.
  apply; make olddefconfig
  apply; make olddefconfig
  check
  echo "== config checked: every required option is set"
  make -j"$(nproc)"
  # Each build makes a new module-signing key, and MODULE_SIG_FORCE refuses modules signed by an old one,
  # so no module from a previous build may survive.
  rm -rf /usr/lib/modules/$KVER
  make INSTALL_MOD_STRIP=1 modules_install
  install -d /boot
  cp -v arch/x86/boot/bzImage /boot/vmlinuz-$KVER-autark
  cp -v System.map /boot/System.map-$KVER
  cp -v .config /boot/config-$KVER
  # The module signing key is needed again for out-of-tree drivers (build guide 6.2); keep it root-only.
  install -d -m 0700 /root/kernel-keys
  install -m 0600 certs/signing_key.pem certs/signing_key.x509 /root/kernel-keys/
) > "$LOG" 2>&1
rc=$?
set -e
if [ "$rc" != 0 ]; then echo "== kernel FAILED (exit $rc); last lines of $LOG:"; tail -40 "$LOG"; exit 1; fi

grep -E '^(== |MISMATCH)' "$LOG" || true
echo "== kernel $KVER built: $(du -h /boot/vmlinuz-$KVER-autark | cut -f1), $(find /usr/lib/modules/$KVER -name '*.ko*' | wc -l) modules"
