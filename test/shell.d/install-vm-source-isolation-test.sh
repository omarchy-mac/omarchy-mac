#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

# Exercise source staging without root or an actual guest. The guest identity
# deliberately differs from the host, as it does on GitHub-hosted runners.
eval "$(sed -n '/^stage_source() {/,/^}/p' "$ROOT/test/vm/run-selective-edge")"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
ROOT="$test_tmp/checkout"
SOURCE="$test_tmp/source"
GUEST_USER=ci
mkdir -p "$ROOT/.git" "$SOURCE"
printf 'original\n' >"$ROOT/install.sh"
printf 'ref: refs/heads/test\n' >"$ROOT/.git/HEAD"
nspawn() {
  [[ $1 == "id" && $3 == "$GUEST_USER" ]] || fail "unexpected guest operation"
  if [[ $2 == "-u" ]]; then echo 12345; else echo 23456; fi
}
as_root() {
  if [[ $1 == "chown" ]]; then
    printf '%s\n' "$*" >"$test_tmp/chown"
  else
    "$@"
  fi
}
stage_source
[[ $(cat "$test_tmp/chown") == "chown -R 12345:23456 $SOURCE" ]] ||
  fail "source staging must use guest ownership only on its private copy"
cmp "$ROOT/.git/HEAD" "$SOURCE/.git/HEAD" || fail "staging must retain git metadata for package builds"
printf 'guest writes\n' >"$SOURCE/install.sh"
[[ $(cat "$ROOT/install.sh") == "original" ]] || fail "guest writes must not affect the checkout"
pass "guest source staging preserves git metadata and isolates mismatched UID ownership"
