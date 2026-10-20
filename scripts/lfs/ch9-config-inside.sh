#!/bin/bash
# Build guide Step 6.1 and 6.4: system identity and configuration (LFS 13.1-systemd chapters 9-10), and zram.
# Runs INSIDE the chroot as root, started by ch7-chroot.sh with INSIDE=ch9-config-inside.sh. Safe to re-run:
# every file is written whole. Values come from decisions.md and the Ubuntu host's settings (log.md).
set -euo pipefail

if [ ! -e /sources/wget-list-systemd ] || grep -qi ubuntu /etc/os-release 2>/dev/null; then
  echo "ch9-config-inside.sh: not inside the Autark chroot; refusing to run" >&2
  exit 1
fi

# Identity (build guide 6.1). /etc/hosts replaces chapter 7's, which carried the build host's name.
echo autark > /etc/hostname
cat > /etc/hosts << "EOF"
127.0.0.1  localhost
127.0.1.1  autark
::1        localhost
EOF
cat > /etc/os-release << "EOF"
NAME="Autark"
ID=autark
PRETTY_NAME="Autark"
VERSION_ID="0.1"
EOF

# Network: systemd-networkd, DHCP on any wired interface (LFS 9.2 DHCP example, matched by type instead of
# a device name). Wi-Fi needs iwd or wpa_supplicant from BLFS and comes with Step 8.
mkdir -p /etc/systemd/network /etc/systemd/resolved.conf.d
cat > /etc/systemd/network/10-wired-dhcp.network << "EOF"
[Match]
Type=ether

[Network]
DHCP=yes
EOF

# DNS (decisions.md): DNS over TLS to Quad9 through systemd-resolved, no plain-DNS fallback.
cat > /etc/systemd/resolved.conf.d/autark-dns.conf << "EOF"
[Resolve]
DNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net 2620:fe::9#dns.quad9.net
DNSOverTLS=yes
FallbackDNS=
EOF

# Clock (LFS 9.4): hardware clock in UTC, as the Ubuntu host has it (LocalRTC=no); timesyncd stays enabled.
cat > /etc/adjtime << "EOF"
0.0 0 0.0
0
UTC
EOF

# Console and locale, copied from the Ubuntu host: keymap us, LANG=en_US.UTF-8 (LFS 9.5, 9.6).
cat > /etc/vconsole.conf << "EOF"
KEYMAP=us
FONT=Lat2-Terminus16
EOF
cat > /etc/locale.conf << "EOF"
LANG=en_US.UTF-8
EOF

# LFS 9.6 /etc/profile, 9.7 /etc/inputrc, 9.8 /etc/shells: the book's files, verbatim.
cat > /etc/profile << "EOF"
# Begin /etc/profile

for i in $(locale); do
  unset ${i%=*}
done

if [[ "$TERM" = linux ]]; then
  export LANG=C.UTF-8
else
  source /etc/locale.conf

  for i in $(locale); do
    key=${i%=*}
    if [[ -v $key ]]; then
      export $key
    fi
  done
fi

# End /etc/profile
EOF

cat > /etc/inputrc << "EOF"
# Begin /etc/inputrc
# Modified by Chris Lynn <roryo@roryo.dynup.net>

# Allow the command prompt to wrap to the next line
set horizontal-scroll-mode Off

# Enable 8-bit input
set meta-flag On
set input-meta On

# Turns off 8th bit stripping
set convert-meta Off

# Keep the 8th bit for display
set output-meta On

# none, visible or audible
set bell-style none

# All of the following map the escape sequence of the value
# contained in the 1st argument to the readline specific functions
"\eOd": backward-word
"\eOc": forward-word

# for linux console
"\e[1~": beginning-of-line
"\e[4~": end-of-line
"\e[5~": beginning-of-history
"\e[6~": end-of-history
"\e[3~": delete-char
"\e[2~": quoted-insert

# for xterm
"\eOH": beginning-of-line
"\eOF": end-of-line

# for Konsole
"\e[H": beginning-of-line
"\e[F": end-of-line

# uncomment for history search mode with up/down
# "\e[A": history-search-backward
# "\e[B": history-search-forward

# End /etc/inputrc
EOF

cat > /etc/shells << "EOF"
# Begin /etc/shells

/bin/sh
/bin/bash

# End /etc/shells
EOF

# Filesystems (LFS 10.2), by the names and UUIDs that travel with the partitions to the real disk (Step 7b).
# Root is unlocked by the initramfs (rd.luks.name on the kernel command line); /home by crypttab below.
cat > /etc/fstab << "EOF"
# Begin /etc/fstab

# file system            mount-point  type  options                 dump  fsck
/dev/mapper/autark       /            ext4  defaults                1     1
/dev/mapper/autark-home  /home        ext4  defaults,nodev,nosuid   1     2
UUID=52E1-3F24           /boot/efi    vfat  umask=0077,shortname=winnt  0  2

# End /etc/fstab
EOF

# /home unlocks with a key file kept inside the (already unlocked) root, so the PIN is entered once
# (build guide Step 1). The key is created here; adding it to /home's LUKS header happens on the host.
install -d -m 0700 /etc/cryptsetup-keys.d
[ -s /etc/cryptsetup-keys.d/autark-home.key ] || \
  ( umask 077; dd if=/dev/urandom of=/etc/cryptsetup-keys.d/autark-home.key bs=512 count=8 status=none )
chmod 0400 /etc/cryptsetup-keys.d/autark-home.key
# The /home LUKS volume's UUID belongs to one disk image, so it is given, not written here (the installer, scripts/autark-install.sh,
# writes its own crypttab).
: "${HOME_LUKS_UUID:?set HOME_LUKS_UUID to the UUID of the home LUKS volume of the image}"
cat > /etc/crypttab << EOF
# name       device                                     key file                                   options
autark-home  UUID=$HOME_LUKS_UUID  /etc/cryptsetup-keys.d/autark-home.key  luks
EOF

# zram swap (build guide 6.4): a zstd device of half the RAM, created at boot. The logic lives in a script:
# systemd expands $VAR inside ExecStart= itself, which would empty the shell's own variables.
install -d /usr/lib/autark
cat > /usr/lib/autark/zram-swap << "EOF"
#!/bin/bash
# Start or stop compressed swap in RAM: zstd, half of memory. Used by zram-swap.service.
set -euo pipefail
case "${1:?start|stop}" in
  start)
    modprobe zram num_devices=0 2>/dev/null || true
    kib=$(awk '/MemTotal/{print int($2/2)}' /proc/meminfo)
    dev=$(zramctl --find --algorithm zstd --size "${kib}KiB")
    mkswap -U clear "$dev" > /dev/null
    swapon --priority 100 "$dev"
    echo "$dev" > /run/zram-swap.dev
    ;;
  stop)
    dev=$(cat /run/zram-swap.dev)
    swapoff "$dev"
    zramctl --reset "$dev"
    ;;
esac
EOF
chmod 0755 /usr/lib/autark/zram-swap
cat > /etc/systemd/system/zram-swap.service << "EOF"
[Unit]
Description=Compressed swap in RAM (zram, zstd, half of memory)
DefaultDependencies=no
Before=swap.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/lib/autark/zram-swap start
ExecStop=/usr/lib/autark/zram-swap stop

[Install]
WantedBy=swap.target
EOF
systemctl enable zram-swap.service
echo "== configuration done"
