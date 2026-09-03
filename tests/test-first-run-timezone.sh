#!/bin/bash
# Checks when the first-run timezone prompt fires. A machine on the image's
# default has never been told where it is; one that has been set should not be
# nagged. Needs no root: timedatectl is stubbed on PATH.

set -uo pipefail

LEAF="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/install/user/first-run/timezone.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
pass=0
failures=0

check() {
  local label="$1"
  shift
  if "$@"; then
    echo "✓ $label"
    ((++pass))
  else
    echo "✗ $label"
    ((++failures))
  fi
}

not() {
  ! "$@"
}

# The leaf is sourced by the first-run driver, so it is sourced here too, with
# the notification recorded as a file rather than sent.
prompts_for_timezone() {
  local timezone="$1"
  rm -rf "$WORK/bin" "$WORK/notified"
  mkdir -p "$WORK/bin"
  printf '#!/bin/bash\necho %s\n' "$timezone" >"$WORK/bin/timedatectl"
  printf '#!/bin/bash\ntouch "%s/notified"\n' "$WORK" >"$WORK/bin/omarchy-notification-send"
  chmod +x "$WORK/bin"/*

  PATH="$WORK/bin:$PATH" bash -c "source '$LEAF'" >/dev/null 2>&1
  [[ -e $WORK/notified ]]
}

does_not_prompt_when_executed() {
  local timezone="$1"
  rm -rf "$WORK/bin" "$WORK/notified"
  mkdir -p "$WORK/bin"
  printf '#!/bin/bash\necho %s\n' "$timezone" >"$WORK/bin/timedatectl"
  printf '#!/bin/bash\ntouch "%s/notified"\n' "$WORK" >"$WORK/bin/omarchy-notification-send"
  chmod +x "$WORK/bin"/*

  PATH="$WORK/bin:$PATH" bash "$LEAF" >/dev/null 2>&1
  [[ ! -e $WORK/notified ]]
}

check "a machine still on UTC is prompted" prompts_for_timezone UTC
check "a machine with a real zone is left alone" \
  not prompts_for_timezone America/New_York
check "an unset timezone is prompted" prompts_for_timezone ""
check "another real zone is left alone" not prompts_for_timezone Europe/London
check "a real zone is left alone when the leaf is executed" \
  does_not_prompt_when_executed America/Los_Angeles

echo
echo "=== $pass checks passed, $failures failed ==="
(( failures == 0 ))
