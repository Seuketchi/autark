# Shared by the chapter scripts (sourced, not run). The caller sets `srcdir` (where the tarballs are)
# and `logs`, and defines one pkg_* function per package holding the book's commands.
#
# Two traps this avoids, both hit on 2026-10-16:
# - errexit is ignored for everything inside an `if`/`!`/`&&`/`||` condition, subshells included,
#   so `if ! ( set -e; pkg ); then` lets a failed `make` carry on. The subshell runs as a plain command.
# - `tar -tf | head -1` kills tar with SIGPIPE, which pipefail turns into a silent exit; sed reads it all.

# Unpack a tarball, run the build function inside it, then remove the source tree (book convention).
build() {
  local tarball=$1 fn=$2 dir start rc
  # First entry's top folder. Print it always: "name/", "name/file", "./name/…" and a bare "name" (OpenSSH lists its
  # folder without the slash, which a print-only-on-substitution sed turned into an empty name).
  dir=$(tar -tf "$srcdir/$tarball" | sed -n '1{s|^\./||;s|/.*||;p}')
  [ -n "$dir" ] || { echo "== $fn: can't tell $tarball's top folder"; exit 1; }
  cd "$srcdir"
  rm -rf "$dir"
  tar -xf "$tarball"
  cd "$dir"
  start=$(date +%s)
  echo "== $fn ($dir): started $(date +%T)"
  set +e
  ( set -e; "$fn" ) > "$logs/$fn.log" 2>&1
  rc=$?
  set -e
  if [ "$rc" != 0 ]; then
    echo "== $fn: FAILED (exit $rc); last lines of $logs/$fn.log:"
    tail -25 "$logs/$fn.log"
    exit 1
  fi
  echo "== $fn: done in $(( $(date +%s) - start ))s"
  cd "$srcdir"
  rm -rf "$dir"
}
