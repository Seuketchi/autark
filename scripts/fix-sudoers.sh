#!/bin/sh
# Replaces the broken /etc/sudoers.d/8c-build with the intended rule: tan may run exactly two commands as root
# without a password (the phase 8c build script, and the cp that updates it). Run as root:
#   su -c 'sh /home/tan/fix-sudoers.sh'
# Remove the rule when the browser is built:  su -c 'rm /etc/sudoers.d/8c-build'
set -e
cat > /etc/sudoers.d/8c-build <<'EOF'
tan ALL=(root) NOPASSWD: \
  /usr/bin/bash /sources/8b/phase8c-inside.sh, \
  /usr/bin/cp /home/tan/browser-src/phase8c-inside.sh /sources/8b/phase8c-inside.sh
EOF
chmod 440 /etc/sudoers.d/8c-build
echo "written; check with: sudo -n -l"
