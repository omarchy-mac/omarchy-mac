#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/omarchy-hw-nvidia-gsp" <<'SH'
#!/bin/bash
exit 1
SH

cat >"$stub_bin/omarchy-hw-nvidia-without-gsp" <<'SH'
#!/bin/bash
exit 1
SH

cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
touch "$OMARCHY_TEST_PKG_ADD_CALLED"
exit 99
SH

chmod +x "$stub_bin"/*

export OMARCHY_TEST_PKG_ADD_CALLED="$test_tmp/pkg-add-called"

if ! PATH="$stub_bin:$ROOT/bin:$PATH" bash "$ROOT/bin/omarchy-install-gaming-gpu-lib32" >"$test_tmp/output" 2>&1; then
  fail "the GPU helper succeeds when no supported GPU is detected"
fi

[[ ! -e $OMARCHY_TEST_PKG_ADD_CALLED ]] ||
  fail "the GPU helper does not try to install an empty package list"
grep -Fq 'No supported GPU detected' "$test_tmp/output" ||
  fail "the GPU helper explains why it skipped lib32 drivers"
pass "the GPU helper treats an unsupported GPU as a successful no-op"
