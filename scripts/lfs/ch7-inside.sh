#!/bin/bash
# Build guide Step 4, part 2: LFS 13.1-systemd chapter 7, the part that runs INSIDE the chroot, as root.
# Commands are the book's, verbatim. Started by ch7-chroot.sh; never run it on the host.
# Each phase runs once: a marker in /sources/.done/ skips it on a re-run.
set -euo pipefail

# Refuse to run on the host: /sources only exists inside the chroot, and the host is Ubuntu.
if [ ! -e /sources/wget-list-systemd ] || grep -qi ubuntu /etc/os-release 2>/dev/null; then
  echo "ch7-inside.sh: not inside the Autark chroot; refusing to run" >&2
  exit 1
fi

logs=/sources/logs
mkdir -p "$logs" /sources/.done
srcdir=/sources
source "$(dirname "$0")/build-lib.sh"


# 7.5
phase_dirs() {
  mkdir -pv /{boot,home,mnt,opt,srv}
  mkdir -pv /etc/{opt,sysconfig}
  mkdir -pv /lib/firmware
  mkdir -pv /media/{floppy,cdrom}
  mkdir -pv /usr/{,local/}{include,src}
  mkdir -pv /usr/lib/locale
  mkdir -pv /usr/local/{bin,lib,sbin}
  mkdir -pv /usr/{,local/}share/{color,dict,doc,info,locale,man}
  mkdir -pv /usr/{,local/}share/{misc,terminfo,zoneinfo}
  mkdir -pv /usr/{,local/}share/man/man{1..8}
  mkdir -pv /var/{cache,local,log,mail,opt,spool}
  mkdir -pv /var/lib/{color,misc,locate}

  ln -sfv /run /var/run
  ln -sfv /run/lock /var/lock

  install -dv -m 0750 /root
  install -dv -m 1777 /tmp /var/tmp
}

# 7.6 (the book's `exec /usr/bin/bash --login` only refreshes an interactive prompt, so it's left out)
phase_files() {
  ln -sv /proc/self/mounts /etc/mtab
  cat > /etc/hosts << EOF
127.0.0.1  localhost $(hostname)
::1        localhost
EOF
  cat > /etc/passwd << "EOF"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
systemd-journal-gateway:x:73:73:systemd Journal Gateway:/:/usr/bin/false
systemd-journal-remote:x:74:74:systemd Journal Remote:/:/usr/bin/false
systemd-journal-upload:x:75:75:systemd Journal Upload:/:/usr/bin/false
systemd-network:x:76:76:systemd Network Management:/:/usr/bin/false
systemd-resolve:x:77:77:systemd Resolver:/:/usr/bin/false
systemd-timesync:x:78:78:systemd Time Synchronization:/:/usr/bin/false
systemd-coredump:x:79:79:systemd Core Dumper:/:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
systemd-oom:x:81:81:systemd Out Of Memory Daemon:/:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
EOF
  cat > /etc/group << "EOF"
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
clock:x:14:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
systemd-journal:x:23:
input:x:24:
mail:x:34:
kvm:x:61:
systemd-journal-gateway:x:73:
systemd-journal-remote:x:74:
systemd-journal-upload:x:75:
systemd-network:x:76:
systemd-resolve:x:77:
systemd-timesync:x:78:
systemd-coredump:x:79:
uuidd:x:80:
systemd-oom:x:81:
wheel:x:97:
users:x:999:
nogroup:x:65534:
EOF
  echo "tester:x:101:101::/home/tester:/bin/bash" >> /etc/passwd
  echo "tester:x:101:" >> /etc/group
  install -o tester -d /home/tester
  touch /var/log/{btmp,lastlog,faillog,wtmp}
  chgrp -v utmp /var/log/lastlog
  chmod -v 664  /var/log/lastlog
  chmod -v 600  /var/log/btmp
}

# 7.7–7.14
pkg_gettext() {
  ./configure --disable-shared
  make
  cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
}

pkg_bison() {
  ./configure --prefix=/usr \
              --docdir=/usr/share/doc/bison-3.8.2
  make
  make install
}

pkg_perl() {
  sh Configure -des                                         \
               -D prefix=/usr                               \
               -D vendorprefix=/usr                         \
               -D useshrplib                                \
               -D privlib=/usr/lib/perl5/5.44/core_perl     \
               -D archlib=/usr/lib/perl5/5.44/core_perl     \
               -D sitelib=/usr/lib/perl5/5.44/site_perl     \
               -D sitearch=/usr/lib/perl5/5.44/site_perl    \
               -D vendorlib=/usr/lib/perl5/5.44/vendor_perl \
               -D vendorarch=/usr/lib/perl5/5.44/vendor_perl
  make
  make install
}

pkg_zlib() {
  ./configure --prefix=/usr
  make
  make install
  rm -fv /usr/lib/libz.a
}

pkg_mpdecimal() {
  ./configure --prefix=/usr    \
              --disable-static \
              --docdir=/usr/share/doc/mpdecimal-4.0.1
  make
  make install
}

pkg_python() {
  ./configure --prefix=/usr       \
              --enable-shared     \
              --without-ensurepip \
              --without-static-libpython
  make
  make install
}

pkg_texinfo() {
  ./configure --prefix=/usr
  make
  make install
}

pkg_util_linux() {
  mkdir -pv /var/lib/hwclock
  ./configure --libdir=/usr/lib     \
              --runstatedir=/run    \
              --disable-chfn-chsh   \
              --disable-login       \
              --disable-nologin     \
              --disable-su          \
              --disable-setpriv     \
              --disable-runuser     \
              --disable-pylibmount  \
              --disable-static      \
              --disable-liblastlog2 \
              --without-python      \
              ADJTIME_PATH=/var/lib/hwclock/adjtime \
              --docdir=/usr/share/doc/util-linux-2.42.2
  make
  make install
}

# 7.14, the part inside the chroot
phase_cleanup() {
  rm -rf /usr/share/{info,man,doc}/*
  find /usr/{lib,libexec} -name \*.la -delete
  rm -rf /tools
}

run_once() {
  local name=$1; shift
  if [ -e "/sources/.done/$name" ]; then echo "== $name: already done, skipped"; return; fi
  "$@"
  touch "/sources/.done/$name"
}

phases=("${@:-dirs files gettext bison perl zlib mpdecimal python texinfo util_linux cleanup}")
for p in ${phases[@]}; do
  case $p in
    dirs)       run_once dirs  phase_dirs > "$logs/ch7_dirs.log" 2>&1; echo "== dirs: done" ;;
    files)      run_once files phase_files > "$logs/ch7_files.log" 2>&1; echo "== files: done" ;;
    gettext)    run_once gettext    build gettext-1.0.tar.xz        pkg_gettext ;;
    bison)      run_once bison      build bison-3.8.2.tar.xz        pkg_bison ;;
    perl)       run_once perl       build perl-5.44.0.tar.xz        pkg_perl ;;
    zlib)       run_once zlib       build zlib-1.3.2.tar.gz         pkg_zlib ;;
    mpdecimal)  run_once mpdecimal  build mpdecimal-4.0.1.tar.gz    pkg_mpdecimal ;;
    python)     run_once python     build Python-3.14.7.tar.xz      pkg_python ;;
    texinfo)    run_once texinfo    build texinfo-7.3.tar.xz        pkg_texinfo ;;
    util_linux) run_once util_linux build util-linux-2.42.2.tar.xz pkg_util_linux ;;
    cleanup)    run_once cleanup phase_cleanup; echo "== cleanup: done" ;;
    *) echo "unknown phase: $p" >&2; exit 2 ;;
  esac
done
echo "== chapter 7 (inside) done"
