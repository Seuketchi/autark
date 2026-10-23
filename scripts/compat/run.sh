#!/bin/sh
# compat/run.sh: try to build every package in packages.txt with ark, and record which build and why the rest don't.
# Builds only, nothing is installed: each package that builds lands in the package cache, ready for `ark publish`.
# Run as root, on a quiet machine (builds use every core for a long time):
#
#   sudo scripts/compat/run.sh [packages.txt]
#
#   ARK=/path/to/ark   the ark to use (default: ark). It should have --make-deps, or build tools Arch needs are left out.
#   OUT=dir            where the results go (default: ./compat-results): results.tsv, and logs/<package>.log
#   TIMEOUT=minutes    how long one package may take (default 45)
#   KEEP=1             keep the build folder of a failed package (default: delete it; the log stays)
#   ACTION=build|install   build (default) leaves dependencies unbuilt, so a package whose dependencies are not installed
#                      fails; install builds and installs them too, which is what compat/container.sh uses, in a throwaway system
#
# It can be stopped and started again: a package already in results.tsv is skipped. Delete its line to retry it.

set -u
ARK=${ARK:-ark}
LIST=${1:-$(dirname "$0")/packages.txt}
OUT=${OUT:-$PWD/compat-results}
TIMEOUT=${TIMEOUT:-45}
BUILDS=${BUILDS:-/var/tmp/autark-pkg}
ACTION=${ACTION:-build}

die() { echo "compat/run.sh: $*" >&2; exit 1; }

# NOROOT=1 is for testing this script with a stand-in for ark.
[ "$(id -u)" = 0 ] || [ -n "${NOROOT:-}" ] || die "run it as root: ark build drops to the build user itself"
command -v "$ARK" > /dev/null 2>&1 || die "no $ARK; set ARK=/path/to/ark"
[ -f "$LIST" ] || die "no list at $LIST"

flags="-y"
if "$ARK" --help 2>&1 | grep -q -- --make-deps; then
    flags="$flags --make-deps"
else
    echo "compat/run.sh: this ark has no --make-deps: build tools Arch needs will be left out, and more packages fail" >&2
fi

mkdir -p "$OUT/logs"
results=$OUT/results.tsv
[ -f "$results" ] || printf 'package\tstatus\tseconds\tlast error line\n' > "$results"

while read -r name _; do
    case $name in '' | '#'*) continue ;; esac
    if cut -f1 "$results" | grep -qx "$name"; then
        continue
    fi
    start=$(date +%s)
    # shellcheck disable=SC2086
    nice -n 15 ionice -c3 timeout "${TIMEOUT}m" "$ARK" $flags "$ACTION" "$name" > "$OUT/logs/$name.log" 2>&1
    code=$?
    seconds=$(($(date +%s) - start))
    case $code in
        0) status=ok ;;
        124) status=timeout ;;
        *) status=failed ;;
    esac
    last=
    [ "$status" = ok ] || last=$(grep -E '^ark: |error|Error|failed|No such file|not found|refused' "$OUT/logs/$name.log" | tail -1 | tr '\t' ' ' | cut -c1-160)
    printf '%s\t%s\t%s\t%s\n' "$name" "$status" "$seconds" "$last" >> "$results"
    # A failed build keeps its folder for debugging; across a long list that fills the disk. The log is kept.
    if [ "$status" != ok ] && [ -z "${KEEP:-}" ]; then
        kept=$(sed -n 's/.*the build folder \(.*\) is kept.*/\1/p' "$OUT/logs/$name.log" | tail -1)
        case $kept in "$BUILDS"/*) rm -rf "$kept" ;; esac
    fi
    echo "$status  $name (${seconds}s)"
done < "$LIST"

echo
awk -F'\t' 'NR > 1 { n[$2]++ } END { printf "ok %d, failed %d, timeout %d\n", n["ok"], n["failed"], n["timeout"] }' "$results"
echo "results: $results"
