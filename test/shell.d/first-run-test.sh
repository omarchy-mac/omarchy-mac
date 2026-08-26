#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin" "$test_tmp/home"

cat >"$mock_bin/omarchy-done" <<'SH'
#!/bin/bash
[[ $1 == "check" && $2 == "first-run-user" ]]
SH
cat >"$mock_bin/omarchy-provision-user" <<'SH'
#!/bin/bash
touch "$OMARCHY_TEST_FINALIZE_CALLED"
SH
chmod +x "$mock_bin/omarchy-done" "$mock_bin/omarchy-provision-user"

finalize_called="$test_tmp/finalize-called"
HOME="$test_tmp/home" PATH="$mock_bin:$PATH" OMARCHY_TEST_FINALIZE_CALLED="$finalize_called" \
  bash "$ROOT/bin/omarchy-provision-first-run" >"$test_tmp/output"

[[ ! -e $finalize_called ]] || fail "completed first-run exits before any setup step"
grep -F 'First-run already complete' "$test_tmp/output" >/dev/null || fail "completed first-run reports its lifecycle gate"

if grep -F 'user-migration-notify-watch-enabled' "$ROOT/bin/omarchy-provision-first-run" >/dev/null; then
  fail "first-run does not track the migration watcher separately"
fi
if grep -F 'skip-first-run-update-notification' "$ROOT/install/user/first-run/wifi.sh" >/dev/null; then
  fail "first-run does not track update notifications separately"
fi

cat >"$mock_bin/timedatectl" <<'SH'
#!/bin/bash
printf 'America/Los_Angeles\n'
SH
cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
touch "$OMARCHY_TEST_NOTIFICATION_SENT"
SH
chmod +x "$mock_bin/timedatectl" "$mock_bin/omarchy-notification-send"

if ! OMARCHY_TEST_NOTIFICATION_SENT="$test_tmp/timezone-notification-sent" \
  PATH="$mock_bin:$PATH" bash "$ROOT/install/user/first-run/timezone.sh" \
  >"$test_tmp/timezone-output" 2>&1; then
  fail "timezone first-run step succeeds when timezone is already configured" \
    "$(<"$test_tmp/timezone-output")"
fi
[[ ! -e "$test_tmp/timezone-notification-sent" ]] || \
  fail "timezone first-run step skips configured timezones"

pass "first-run uses one lifecycle completion marker"
