#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

helper="$ROOT/install/helpers/set-arm-mirrors.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"
cat >"$mock_bin/curl" <<'SH'
#!/bin/bash

printf '%s\n' "$@" >"$ARM_MIRROR_TEST_LOG"
SH
chmod +x "$mock_bin/curl"

export ARM_MIRROR_TEST_LOG="$test_tmp/curl-args"
PATH="$mock_bin:$PATH"
export PATH
VERBOSE=0
export VERBOSE

# The helper is also an executable, so source only the connectivity function
# instead of running its mirrorlist writes against the host.
eval "$(awk '/^test_mirror_connectivity\(\) \{/,/^\}/' "$helper")"

test_mirror_connectivity 'http://us.mirror.archlinuxarm.org/$arch/$repo'

if ! grep -Fxq 'http://us.mirror.archlinuxarm.org/aarch64/core' "$ARM_MIRROR_TEST_LOG"; then
  fail "mirror connectivity expands the ARM path" "curl args:\n$(cat "$ARM_MIRROR_TEST_LOG")"
fi
pass "mirror connectivity expands the ARM path"
