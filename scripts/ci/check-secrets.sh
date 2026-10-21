#!/bin/bash
# Fails if a tracked file looks like it holds a secret or a login. Run from anywhere inside the repository.
#   scripts/ci/check-secrets.sh
set -u
cd "$(git rev-parse --show-toplevel)"
bad=0
note() { echo "check-secrets: $*"; bad=1; }

# Private key material anywhere in tracked text files.
if git grep -InE -e '-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY( BLOCK)?-----' -- . ':!scripts/ci/check-secrets.sh'; then
  note "a private key is committed (above)"
fi
# Files that are keys or logins by name.
if git ls-files | grep -E '(^|/)(\.credentials\.json|\.claude\.json|id_(rsa|ed25519|ecdsa)|[^/]*\.(key|p12|pfx|kdbx))$|apollotech-otel-headers'; then
  note "a key or login file is tracked (above)"
fi
# Tokens with a recognisable shape.
if git grep -InE -e 'gh[pousr]_[A-Za-z0-9]{36,}' -e 'github_pat_[A-Za-z0-9_]{50,}' -e 'AKIA[0-9A-Z]{16}' -e 'xox[baprs]-[A-Za-z0-9-]{10,}' -- . ':!scripts/ci/check-secrets.sh'; then
  note "a token is committed (above)"
fi
[ $bad -eq 0 ] && echo "check-secrets: clean"
exit $bad
