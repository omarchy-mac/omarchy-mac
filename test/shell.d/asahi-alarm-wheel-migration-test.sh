#!/bin/bash
#
# The Asahi alarm-in-wheel repair must remove the bootstrap account from wheel
# when a different owner is already an administrator, and must no-op when
# alarm is the owner, missing, already demoted, or the only remaining admin.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration="$ROOT/migrations/1787744855.sh"
[[ -f $migration ]] || fail "alarm-from-wheel migration exists"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

stub_bin="$test_dir/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/id" <<'STUB'
#!/bin/bash
case "${1:-}:${2:-}" in
  -un:)
    printf '%s\n' "${STUB_ME:?}"
    ;;
  -u:alarm)
    [[ ${STUB_ALARM_EXISTS:-0} == 1 ]] || exit 1
    printf '1000\n'
    ;;
  -nG:alarm)
    [[ ${STUB_ALARM_EXISTS:-0} == 1 ]] || exit 1
    printf '%s\n' "${STUB_ALARM_GROUPS:?}"
    ;;
  *)
    exit 1
    ;;
esac
STUB

cat >"$stub_bin/getent" <<'STUB'
#!/bin/bash
[[ $1 == group && $2 == wheel ]] || exit 1
printf 'wheel:x:998:%s\n' "${STUB_WHEEL_MEMBERS:?}"
STUB

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB

cat >"$stub_bin/gpasswd" <<'STUB'
#!/bin/bash
echo "$@" >>"${GPASSWD_CALLS:?}"
STUB

cat >"$stub_bin/uname" <<'STUB'
#!/bin/bash
[[ $1 == -m ]] || exit 1
printf '%s\n' "${STUB_ARCH:-aarch64}"
STUB

chmod +x "$stub_bin/id" "$stub_bin/getent" "$stub_bin/sudo" "$stub_bin/gpasswd" "$stub_bin/uname"

gpasswd_calls="$test_dir/gpasswd-calls"

run_migration() {
  rm -f "$gpasswd_calls"
  STUB_ME="$1" STUB_ALARM_EXISTS="$2" STUB_ALARM_GROUPS="$3" STUB_WHEEL_MEMBERS="$4" \
    STUB_ARCH="${STUB_ARCH:-aarch64}" \
    GPASSWD_CALLS="$gpasswd_calls" PATH="$stub_bin:$PATH" \
    bash -euo pipefail "$migration" >/dev/null
}

# x86_64: a coincidental alarm-in-wheel must not be touched.
STUB_ARCH=x86_64 run_migration naeem 1 "alarm wheel" "alarm,naeem" || fail "migration runs on x86_64"
[[ ! -f $gpasswd_calls ]] || fail "migration must not touch wheel off aarch64"
pass "migration no-ops on x86_64"

# Gap install: owner is not alarm, both are in wheel, alarm is listed first.
run_migration naeem 1 "alarm wheel" "alarm,naeem" || fail "migration runs for a gap install"
[[ -f $gpasswd_calls ]] || fail "migration removes alarm from wheel on a gap install"
grep -qx -- "-d alarm wheel" "$gpasswd_calls" || fail "migration calls gpasswd -d alarm wheel"
pass "migration removes alarm when a different owner is already in wheel"

# Same repair with the owner listed first in /etc/group.
run_migration naeem 1 "alarm wheel" "naeem,alarm" || fail "migration runs when owner is listed first"
grep -qx -- "-d alarm wheel" "$gpasswd_calls" || fail "migration still removes alarm when owner is listed first"
pass "migration does not depend on /etc/group member order"

# The account running migrate is alarm: they chose it as the owner.
run_migration alarm 1 "alarm wheel" "alarm" || fail "migration runs when alarm is the current user"
[[ ! -f $gpasswd_calls ]] || fail "migration must not demote alarm when it is the current user"
pass "migration keeps alarm in wheel when it is the chosen owner"

# No bootstrap account (or a machine that never had one).
run_migration naeem 0 "naeem wheel" "naeem" || fail "migration runs when alarm does not exist"
[[ ! -f $gpasswd_calls ]] || fail "migration must not call gpasswd when alarm is missing"
pass "migration no-ops when alarm does not exist"

# Already repaired, including this machine: alarm exists but is not in wheel.
run_migration naeem 1 "alarm" "naeem" || fail "migration runs when alarm is already out of wheel"
[[ ! -f $gpasswd_calls ]] || fail "migration must not call gpasswd when alarm is already out of wheel"
pass "migration no-ops when alarm is already out of wheel"

# Owner was never added to wheel: demoting alarm would leave no administrator.
run_migration naeem 1 "alarm wheel" "alarm" || fail "migration runs when alarm is the only wheel member"
[[ ! -f $gpasswd_calls ]] || fail "migration must not demote alarm when it is the only administrator"
pass "migration refuses to leave wheel with no administrator"

# A uid-1001 user exists in passwd but is not in wheel. The suggested snippet
# would still gpasswd; this migration must not.
run_migration extra 1 "alarm wheel" "alarm" || fail "migration runs when a non-wheel extra user is current"
[[ ! -f $gpasswd_calls ]] || fail "migration must not use a non-wheel extra user as the owner check"
pass "migration does not demote alarm just because some other user exists"

# Idempotent rerun after a successful repair.
run_migration naeem 1 "alarm wheel" "alarm,naeem" || fail "first repair run succeeds"
run_migration naeem 1 "alarm" "naeem" || fail "second run after repair succeeds"
[[ ! -f $gpasswd_calls ]] || fail "second run must not call gpasswd again"
pass "migration is a no-op on rerun after alarm has left wheel"
