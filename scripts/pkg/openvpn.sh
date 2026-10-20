# openvpn 2.7.8: the client for the .ovpn profiles in ~/.config/openvpn.
# Built with iproute2 (so no data channel offload and no libnl), without LZO, and with OpenSSL. Its sha256 was checked
# against both GitHub's release asset and swupdate.openvpn.org (identical); the .asc signature wasn't, since there's no gpg here.
# VPN DNS goes to systemd-resolved through the dns-updown script it installs in /usr/libexec/openvpn (a bash script).
name=openvpn
version=2.7.8
release=1
description="OpenVPN client and server"
source=(https://swupdate.openvpn.org/community/releases/openvpn-2.7.8.tar.gz)
checksums=(sha256:c070d1d2440b5a6fca6c2c68645c98cd492116ac36ef4f0946177115532c8e36)
depends=(glibc openssl lz4 libcap-ng linux-pam iproute2 systemd bash)
mode=staged

build() {
  ./configure --prefix=/usr          \
              --sysconfdir=/etc      \
              --localstatedir=/var   \
              --disable-static       \
              --disable-lzo          \
              --disable-unit-tests   \
              --enable-iproute2      \
              --enable-systemd       \
              --with-crypto-library=openssl
  make
  make DESTDIR="$DESTDIR" install
}
