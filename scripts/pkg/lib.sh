# Sourced by autark-pkg before every recipe: Autark's build flags (decisions.md, "CPU target" and "Build
# hardening") and the helper the book's commands use. glibc's recipe sets its own flags.
export CFLAGS="-O2 -march=x86-64-v3 -pipe -fstack-protector-strong -fstack-clash-protection -fcf-protection=full -D_FORTIFY_SOURCE=3"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-Wl,-O1 -Wl,-z,relro -Wl,-z,now"
export MAKEFLAGS="-j$(nproc)" TESTSUITEFLAGS="-j$(nproc)"

# A failed test suite is recorded, not fatal (the book lists known failures); autark-pkg prints them at the end.
testfail() {
  echo "== TESTFAIL: $*"
  echo "$(date +%T) $name $version: $*" >> "$LOGS/test-failures.txt"
}
