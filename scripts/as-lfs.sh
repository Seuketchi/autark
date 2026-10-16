#!/usr/bin/env bash
# Run a command as the lfs user with the clean environment from LFS chapter 4.4, without a login shell.
# The book's `su - lfs` starts an interactive shell (and a desktop session) that a script can't drive.
# Usage: scripts/as-lfs.sh '<commands>'
set -euo pipefail

cmd=${1:?usage: as-lfs.sh '<commands>'}
exec sudo -u lfs env -i HOME=/home/lfs TERM="${TERM:-xterm}" \
  /bin/bash -c 'source ~/.bashrc && cd ~ && '"$cmd"
