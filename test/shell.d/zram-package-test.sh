#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1787669934.sh"
[[ -f $migration ]] || fail "the zram package repair migration exists"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
swap_active="$test_tmp/dev-zram0.swap.active"
test_root="$test_tmp/omarchy"
first_home="$test_tmp/first-user-home"
second_home="$test_tmp/second-user-home"
migration_name=$(basename "$migration")
first_marker="$first_home/.local/state/omarchy/migrations/$migration_name"
second_marker="$second_home/.local/state/omarchy/migrations/$migration_name"
mkdir -p "$stub_bin" "$test_root/migrations"
cp "$migration" "$test_root/migrations/$migration_name"

cat >"$stub_bin/omarchy-pkg-missing" <<'STUB'
#!/bin/bash
printf 'missing %s\n' "$*" >>"$TEST_LOG"
(( ${OMARCHY_TEST_ZRAM_MISSING:-1} == 1 ))
STUB

cat >"$stub_bin/omarchy-pkg-add" <<'STUB'
#!/bin/bash
printf 'add %s\n' "$*" >>"$TEST_LOG"
STUB

cat >"$stub_bin/systemctl" <<'STUB'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$TEST_LOG"

case "$1" in
  is-active)
    [[ $2 == "--quiet" && $3 == "dev-zram0.swap" && -e $TEST_SWAP_ACTIVE ]]
    ;;
  start)
    [[ $2 == "systemd-zram-setup@zram0.service" ]]
    touch "$TEST_SWAP_ACTIVE"
    ;;
esac
STUB

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$TEST_LOG"
exec "$@"
STUB

cat >"$stub_bin/omarchy-notification-dismiss" <<'STUB'
#!/bin/bash
exit 0
STUB

chmod +x "$stub_bin"/*

assert_systemd_start_follows_reload() {
  local reload_line start_line

  reload_line=$(awk '$0 == "systemctl daemon-reload" { print NR; exit }' "$calls")
  start_line=$(awk '$0 == "systemctl start systemd-zram-setup@zram0.service" { print NR; exit }' "$calls")
  [[ -n $reload_line && -n $start_line ]] ||
    fail "the zram migration records both systemd calls"
  (( reload_line < start_line )) ||
    fail "the zram migration reloads systemd before starting zram"
}

run_migration() {
  : >"$calls"
  rm -f "$swap_active"
  PATH="$stub_bin:$PATH" TEST_LOG="$calls" TEST_SWAP_ACTIVE="$swap_active" \
    OMARCHY_TEST_ZRAM_MISSING="$1" bash -euo pipefail "$migration" >/dev/null
}

run_migration 1
grep -Fx 'missing zram-generator' "$calls" >/dev/null ||
  fail "the zram migration checks whether zram-generator is installed"
grep -Fx 'add zram-generator' "$calls" >/dev/null ||
  fail "the zram migration installs a missing zram-generator"
grep -Fx 'systemctl daemon-reload' "$calls" >/dev/null ||
  fail "the zram migration reloads systemd after installing zram-generator"
grep -Fx 'systemctl start systemd-zram-setup@zram0.service' "$calls" >/dev/null ||
  fail "the zram migration starts the configured zram device"
assert_systemd_start_follows_reload
pass "the zram migration repairs an existing install without zram-generator"

run_migration 0
! grep -Fx 'add zram-generator' "$calls" >/dev/null ||
  fail "the zram migration does not reinstall an existing zram-generator"
grep -Fx 'systemctl start systemd-zram-setup@zram0.service' "$calls" >/dev/null ||
  fail "the zram migration starts zram when the package is already installed"
assert_systemd_start_follows_reload
pass "the zram migration is idempotent"

run_user_migrations() {
  local home="$1" zram_missing="$2"

  HOME="$home" OMARCHY_PATH="$test_root" PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" TEST_SWAP_ACTIVE="$swap_active" \
    OMARCHY_TEST_ZRAM_MISSING="$zram_missing" \
    "$ROOT/bin/omarchy-migrate" >/dev/null
}

rm -f "$swap_active"
: >"$calls"
run_user_migrations "$first_home" 1
[[ -e $swap_active ]] || fail "the first user activates zram" "$(cat "$calls")"
[[ -e $first_marker ]] || fail "the first user records the zram migration"

: >"$calls"
run_user_migrations "$second_home" 0
[[ -e $second_marker ]] || fail "the second user records the zram migration"
! grep -q '^sudo ' "$calls" ||
  fail "the second user does not repeat privileged zram activation" "$(cat "$calls")"
! grep -Fx 'systemctl daemon-reload' "$calls" >/dev/null ||
  fail "the second user does not reload systemd" "$(cat "$calls")"
! grep -Fx 'systemctl start systemd-zram-setup@zram0.service' "$calls" >/dev/null ||
  fail "the second user does not restart zram" "$(cat "$calls")"
pass "a second user completes the migration without privileged activation"
