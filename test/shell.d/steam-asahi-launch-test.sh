#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
steam_root="$test_home/.local/share/Steam"
launcher="$test_home/.local/share/fex-steam/steam-launcher/bin_steam.sh"
call_log="$test_tmp/muvm-calls"

mkdir -p "$stub_bin" "$steam_root" "$(dirname -- "$launcher")"
touch "$launcher"

cat >"$stub_bin/uname" <<'SH'
#!/bin/bash
if [[ ${1:-} == -m ]]; then
  printf 'aarch64\n'
else
  exec /usr/bin/uname "$@"
fi
SH

cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/muvm" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >"$OMARCHY_TEST_MUVM_LOG"
SH

chmod +x "$stub_bin"/*

run_launcher() {
  HOME="$test_home" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    OMARCHY_TEST_MUVM_LOG="$call_log" \
    bash "$ROOT/bin/omarchy-launch-steam" "$@"
}

run_launcher --first-run "steam://open test"

grep -Fxq -- "-cef-force-occlusion" "$call_log" ||
  fail "fresh Steam launch keeps the Apple Silicon occlusion workaround"
for suppressed_flag in -noverifyfiles -nobootstrapupdate -skipinitialbootstrap -norepairfiles; do
  if grep -Fqx -- "$suppressed_flag" "$call_log"; then
    fail "fresh Steam launch does not pass $suppressed_flag before bootstrap"
  fi
done
grep -Fxq -- "steam://open test" "$call_log" ||
  fail "fresh Steam launch preserves arguments containing spaces"
pass "fresh Steam launches without bootstrap suppression flags"

mkdir -p "$steam_root/steamui"
touch "$steam_root/steamui.so"
run_launcher --root-level-only

for suppressed_flag in -noverifyfiles -nobootstrapupdate -skipinitialbootstrap -norepairfiles; do
  if grep -Fqx -- "$suppressed_flag" "$call_log"; then
    fail "a root-level steamui.so does not falsely mark Steam as bootstrapped"
  fi
done
pass "a root-level steamui.so does not falsely mark Steam as bootstrapped"

mkdir -p "$steam_root/ubuntu12_32"
touch "$steam_root/ubuntu12_32/steamui.so"
run_launcher --existing

for suppressed_flag in -noverifyfiles -nobootstrapupdate -skipinitialbootstrap -norepairfiles; do
  grep -Fxq -- "$suppressed_flag" "$call_log" ||
    fail "bootstrapped Steam launch keeps $suppressed_flag"
done
pass "bootstrapped Steam launches with persistent workaround flags"
