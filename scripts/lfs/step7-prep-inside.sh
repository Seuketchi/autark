#!/bin/bash
# Before build guide Step 7b: the firewall (decisions.md: nftables, block all incoming) and the SOF audio
# firmware. Runs INSIDE the chroot as root, started by ch7-chroot.sh with INSIDE=step7-prep-inside.sh.
# libmnl matches its BLFS md5; libnftnl and nftables aren't in BLFS. netfilter.org refuses automated downloads,
# so all three come from Debian's archive as the untouched upstream tarballs, verified against the Netfilter
# Core Team's own signatures (log.md, 2026-10-17 "Firewall and audio firmware").
set -euo pipefail

if [ ! -e /sources/wget-list-systemd ] || grep -qi ubuntu /etc/os-release 2>/dev/null; then
  echo "step7-prep-inside.sh: not inside the Autark chroot; refusing to run" >&2
  exit 1
fi

logs=/sources/logs
mkdir -p "$logs" /sources/.done /sources/.track /var/lib/autark/files
srcdir=/sources
source "$(dirname "$0")/build-lib.sh"

export CFLAGS="-O2 -march=x86-64-v3 -pipe -fstack-protector-strong -fstack-clash-protection -fcf-protection=full -D_FORTIFY_SOURCE=3"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-Wl,-O1 -Wl,-z,relro -Wl,-z,now"

snapshot() {
  find / -xdev \( -path /sources -o -path /tmp -o -path /root -o -path /var/lib/autark \) -prune \
    -o \( -type f -o -type l \) -print | LC_ALL=C sort
}

run_pkg() {
  local name=$1 tarball=$2 fn=$3
  if [ -e "/sources/.done/prep-$name" ]; then echo "== $name: already done, skipped"; return; fi
  snapshot > /sources/.track/before
  if [ "$tarball" = - ]; then
    echo "== $fn: started $(date +%T)"
    set +e; ( set -e; cd /sources; "$fn" ) > "$logs/$fn.log" 2>&1; local rc=$?; set -e
    if [ "$rc" != 0 ]; then echo "== $fn: FAILED (exit $rc)"; tail -25 "$logs/$fn.log"; exit 1; fi
    echo "== $fn: done"
  else
    build "$tarball" "$fn"
  fi
  snapshot | LC_ALL=C comm -13 /sources/.track/before - > "/var/lib/autark/files/$name"
  echo "   $(wc -l < "/var/lib/autark/files/$name") new files tracked"
  touch "/sources/.done/prep-$name"
}

# BLFS libmnl (without its optional Doxygen docs).
pkg_libmnl() {
  ./configure --prefix=/usr --disable-static &&
  make
  make install
}

pkg_libnftnl() {
  ./configure --prefix=/usr --disable-static
  make
  make install
}

# No man pages (need asciidoc), no JSON (needs jansson); the interactive shell uses readline (1.1.7 defaults
# to libedit, which Autark doesn't have).
pkg_nftables() {
  ./configure --prefix=/usr --sysconfdir=/etc --disable-static --disable-debug --disable-man-doc --with-cli=readline
  make
  make install
}

# The ruleset: drop everything coming in except replies to Autark's own connections and the control messages
# networking can't work without. Nothing is forwarded. Outgoing traffic is unrestricted.
step_firewall() {
  install -d /etc/nftables.d
  cat > /etc/nftables.conf << "EOF"
#!/usr/sbin/nft -f
# Autark firewall (decisions.md: block all incoming connections, no services listening).
flush ruleset

table inet autark {
  chain input {
    type filter hook input priority filter; policy drop;

    ct state invalid drop
    ct state established,related accept
    iif lo accept

    # IPv6 can't work without neighbour discovery and router adverts, and path-MTU needs "too big".
    icmpv6 type { destination-unreachable, packet-too-big, time-exceeded, parameter-problem,
                  nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert, mld-listener-query } accept
    # IPv4 error messages that belong to Autark's own connections (path MTU, unreachable).
    icmp type { destination-unreachable, time-exceeded, parameter-problem } accept
    # DHCPv6 replies to the client (systemd-networkd), only from link-local servers.
    ip6 saddr fe80::/10 udp dport 546 accept

    # Local additions, one file per purpose, e.g. /etc/nftables.d/ssh.nft.
    include "/etc/nftables.d/*.nft"
  }

  chain forward {
    type filter hook forward priority filter; policy drop;
  }

  chain output {
    type filter hook output priority filter; policy accept;
  }
}
EOF
  # An include with no matching files is an error in nft, so keep one harmless placeholder.
  [ -e /etc/nftables.d/00-empty.nft ] || echo "# Local input rules go in files like this one." > /etc/nftables.d/00-empty.nft

  cat > /etc/systemd/system/nftables.service << "EOF"
[Unit]
Description=Firewall: block all incoming (nftables)
DefaultDependencies=no
Wants=network-pre.target
Before=network-pre.target shutdown.target
Conflicts=shutdown.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/nftables.conf
ExecReload=/usr/sbin/nft -f /etc/nftables.conf
ExecStop=/usr/sbin/nft flush ruleset

[Install]
WantedBy=sysinit.target
EOF
  systemctl enable nftables.service
}

# SOF audio firmware (sof-bin, not in linux-firmware): the Intel-signed builds for Raptor Lake, in both message
# protocols (IPC3 is what Ubuntu used; newer kernels may choose IPC4), with the topology this laptop loads.
# The audio DSP of a retail laptop only runs Intel-signed firmware.
step_sof() {
  local t S; t=$(mktemp -d); S=sof-bin-2026.09.2
  tar -xzf /sources/$S.tar.gz -C "$t" \
    $S/sof/intel-signed/sof-adl.ri $S/sof-ipc4/rpl/intel-signed/sof-rpl.ri \
    $S/sof-tplg/sof-hda-generic-2ch.tplg $S/sof-ipc4-tplg/sof-hda-generic-2ch.tplg
  # IPC3: Raptor Lake runs Alder Lake's firmware; sof-bin ships sof-rpl.ri as a link to sof-adl.ri, kept as such.
  install -vDm644 "$t/$S/sof/intel-signed/sof-adl.ri"            /usr/lib/firmware/intel/sof/sof-adl.ri
  ln -sfv sof-adl.ri                                              /usr/lib/firmware/intel/sof/sof-rpl.ri
  install -vDm644 "$t/$S/sof-ipc4/rpl/intel-signed/sof-rpl.ri"   /usr/lib/firmware/intel/sof-ipc4/rpl/sof-rpl.ri
  install -vDm644 "$t/$S/sof-tplg/sof-hda-generic-2ch.tplg"      /usr/lib/firmware/intel/sof-tplg/sof-hda-generic-2ch.tplg
  install -vDm644 "$t/$S/sof-ipc4-tplg/sof-hda-generic-2ch.tplg" /usr/lib/firmware/intel/sof-ipc4-tplg/sof-hda-generic-2ch.tplg
  rm -rf "$t"
}

run_pkg libmnl   libmnl_1.0.5.orig.tar.bz2    pkg_libmnl
run_pkg libnftnl libnftnl_1.3.2.orig.tar.xz   pkg_libnftnl
run_pkg nftables nftables_1.1.7.orig.tar.xz   pkg_nftables
run_pkg firewall -                            step_firewall
run_pkg sof      -                            step_sof
echo "== firewall and audio firmware done"
