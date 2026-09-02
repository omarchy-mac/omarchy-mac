#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command jq
require_command python3

migration="${MIGRATION_OVERRIDE:-$ROOT/migrations/1786643346.sh}"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
profile_root="$home/.config/chromium"
preferences="$profile_root/Default/Preferences"
mkdir -p "$(dirname "$preferences")"

# Any id Chromium once derived from the extension's keyless load path; the
# repair keys off the registered command name, not the id.
ghost_id="ikkebdkaanlebnifjnbeiaklodhbjcci"
pinned_id="bgpiichlckmfanooecilcjemknkcpngb"

write_stale_preferences() {
  jq -n --arg ghost "$ghost_id" --arg pinned "$pinned_id" '{extensions: {commands: {"linux:Alt+Shift+L": {command_name: "copy-url", extension: $ghost, global: false}}, settings: {($ghost): {commands: {"copy-url": {suggested_key: "Alt+Shift+L", was_assigned: true}}}, ($pinned): {commands: {"copy-url": {suggested_key: "Alt+Shift+L"}}}}}}' >"$preferences"
}

stub_bin="$test_dir/bin"
mkdir -p "$stub_bin"

REAL_PYTHON=$(command -v python3)
export REAL_PYTHON
local_host=$(hostname)
live_pid=""
socket_pid=""

run_migration() {
  HOME="$home" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >/dev/null 2>&1
}

# A running Chromium-family browser marks its profile root with a SingletonLock
# symlink to <hostname>-<pid>, a target that never exists on disk. A dead local
# PID is stale; a live PID is classified by its executable basename.
open_browser() {
  mkdir -p "$profile_root"
  ln -sfn "$local_host-999999" "$profile_root/SingletonLock"
}
close_browser() {
  rm -f "$profile_root/SingletonLock" "$profile_root/SingletonSocket" "$profile_root/SingletonCookie"
}
open_process() {
  open_process_at "$profile_root" "$1"
}
open_process_at() {
  local process_root="$1" process_name="$2"
  ln -s "$(command -v sleep)" "$test_dir/$process_name"
  "$test_dir/$process_name" 30 &
  live_pid=$!
  for _ in {1..20}; do
    kill -0 "$live_pid" 2>/dev/null && break
    sleep 0.05
  done
  kill -0 "$live_pid" 2>/dev/null || fail "test process did not start"
  ln -sfn "$local_host-$live_pid" "$process_root/SingletonLock"
}
close_process() {
  if [[ -n $live_pid ]]; then
    kill "$live_pid" 2>/dev/null || true
    wait "$live_pid" 2>/dev/null || true
    live_pid=""
  fi
  rm -f "$test_dir/chromium" "$test_dir/not-browser" "$test_dir/vivaldi-bin"
}
open_socket() {
  SOCKET_PATH="$profile_root/SingletonSocket" "$REAL_PYTHON" -c '
import os, socket, time
server = socket.socket(socket.AF_UNIX)
server.bind(os.environ["SOCKET_PATH"])
server.listen(1)
time.sleep(30)
' &
  socket_pid=$!
  for _ in {1..20}; do
    [[ -S $profile_root/SingletonSocket ]] && break
    sleep 0.05
  done
  [[ -S $profile_root/SingletonSocket ]] || fail "test socket did not start"
}
close_socket() {
  if [[ -n $socket_pid ]]; then
    kill "$socket_pid" 2>/dev/null || true
    wait "$socket_pid" 2>/dev/null || true
    socket_pid=""
  fi
  rm -f "$profile_root/SingletonSocket"
}

# A dead local PID is stale even though SingletonLock remains a dangling
# symlink, so the migration repairs the profile and keeps the artifact.
printf '#!/bin/bash\nexit 1\n' >"$stub_bin/gum"
chmod +x "$stub_bin/gum"
write_stale_preferences
open_browser

run_migration || fail "migration repairs after a stale local SingletonLock"
jq -e --arg pinned "$pinned_id" '.extensions.commands["linux:Alt+Shift+L"].extension == $pinned' "$preferences" >/dev/null ||
  fail "migration repairs despite a stale dangling SingletonLock"
[[ -L $profile_root/SingletonLock ]] || fail "migration preserves the stale SingletonLock artifact"
pass "migration classifies a dead local SingletonLock PID as stale"
rm -f "$preferences.omarchy-copy-url-repair.bak"

# A regular legacy lock remains conservative and prompts before mutation.
write_stale_preferences
close_browser
touch "$profile_root/SingletonLock"
before_hash=$(sha256sum "$preferences" | cut -d' ' -f1)
run_migration && fail "migration defers while a regular SingletonLock exists"
[[ $(sha256sum "$preferences" | cut -d' ' -f1) == "$before_hash" ]] ||
  fail "migration leaves preferences alone while a regular SingletonLock exists"
pass "migration defers on a regular legacy SingletonLock"

# gum paints its prompt on stderr, so that stream has to stay attached:
# suppressing it leaves gum reading keys behind an unpainted screen, which
# reads as a hung update.
cat >"$stub_bin/gum" <<'STUB'
#!/bin/bash
echo "gum-prompt-painted" >&2
exit 1
STUB
prompt_stderr="$test_dir/prompt-stderr"
HOME="$home" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >/dev/null 2>"$prompt_stderr" &&
  fail "migration defers when the browser prompt is declined"
grep -q "gum-prompt-painted" "$prompt_stderr" || fail "migration keeps the browser prompt visible"
pass "migration keeps the browser prompt visible"
rm -f "$profile_root/SingletonLock"

# A browser holding a different profile root cannot revert this repair, so it
# must not hold the update: the repair goes through without ever reaching the
# prompt, which the still-declining gum stub would otherwise fail.
close_browser
mkdir -p "$home/.config/google-chrome"
ln -sfn "foreign-host-999999" "$home/.config/google-chrome/SingletonLock"
write_stale_preferences
run_migration || fail "migration repairs while a different profile root is open"
jq -e --arg pinned "$pinned_id" '.extensions.commands["linux:Alt+Shift+L"].extension == $pinned' "$preferences" >/dev/null ||
  fail "migration repairs the shortcut while a different profile root is open"
pass "migration ignores a browser on a different profile root"
rm -f "$home/.config/google-chrome/SingletonLock" "$preferences.omarchy-copy-url-repair.bak"

# Foreign-host and malformed targets are ambiguous and defer without changing
# the profile. Dangling socket/cookie residue alone is not an active browser.
for lock_target in "foreign-host-999999" "malformed-target"; do
  write_stale_preferences
  ln -sfn "$lock_target" "$profile_root/SingletonLock"
  before_hash=$(sha256sum "$preferences" | cut -d' ' -f1)
  run_migration && fail "migration defers on lock target $lock_target"
  [[ $(sha256sum "$preferences" | cut -d' ' -f1) == "$before_hash" ]] ||
    fail "migration leaves preferences alone for lock target $lock_target"
  rm -f "$profile_root/SingletonLock"
done
ln -s "$profile_root/missing-socket" "$profile_root/SingletonSocket"
ln -s "$profile_root/missing-cookie" "$profile_root/SingletonCookie"
write_stale_preferences
run_migration || fail "migration ignores dangling socket and cookie residue"
[[ -L $profile_root/SingletonSocket && -L $profile_root/SingletonCookie ]] ||
  fail "migration preserves dangling socket and cookie residue"
pass "migration defers ambiguous locks and ignores dangling socket residue"
rm -f "$preferences.omarchy-copy-url-repair.bak" "$profile_root/SingletonSocket" "$profile_root/SingletonCookie"

# A real Unix SingletonSocket proves ownership even without a usable lock
# target, while an executable-backed Chromium PID does the same through the
# host/PID target.
write_stale_preferences
open_socket
before_hash=$(sha256sum "$preferences" | cut -d' ' -f1)
run_migration && fail "migration defers while SingletonSocket is active"
[[ $(sha256sum "$preferences" | cut -d' ' -f1) == "$before_hash" ]] ||
  fail "migration leaves preferences alone while SingletonSocket is active"
close_socket
pass "migration defers on an active SingletonSocket"

write_stale_preferences
open_process chromium
before_hash=$(sha256sum "$preferences" | cut -d' ' -f1)
run_migration && fail "migration defers for a live Chromium-family PID"
[[ $(sha256sum "$preferences" | cut -d' ' -f1) == "$before_hash" ]] ||
  fail "migration leaves preferences alone for a live Chromium-family PID"
close_process
rm -f "$profile_root/SingletonLock"
pass "migration recognizes a live Chromium-family executable"

vivaldi_profile_root="$home/.config/vivaldi"
vivaldi_preferences="$vivaldi_profile_root/Default/Preferences"
mkdir -p "$(dirname "$vivaldi_preferences")"
jq -n --arg ghost "$ghost_id" --arg pinned "$pinned_id" '{extensions: {commands: {"linux:Alt+Shift+L": {command_name: "copy-url", extension: $ghost, global: false}}, settings: {($ghost): {commands: {"copy-url": {suggested_key: "Alt+Shift+L", was_assigned: true}}}, ($pinned): {commands: {"copy-url": {suggested_key: "Alt+Shift+L"}}}}}}' >"$vivaldi_preferences"
open_process_at "$vivaldi_profile_root" vivaldi-bin
before_hash=$(sha256sum "$vivaldi_preferences" | cut -d' ' -f1)
run_migration && fail "migration defers for a live Vivaldi PID"
[[ $(sha256sum "$vivaldi_preferences" | cut -d' ' -f1) == "$before_hash" ]] ||
  fail "migration leaves preferences alone for a live Vivaldi PID"
close_process
rm -f "$vivaldi_profile_root/SingletonLock"
pass "migration recognizes Vivaldi's vivaldi-bin executable"

write_stale_preferences
open_process not-browser
run_migration || fail "migration treats a live non-browser PID as stale"
jq -e --arg pinned "$pinned_id" '.extensions.commands["linux:Alt+Shift+L"].extension == $pinned' "$preferences" >/dev/null ||
  fail "migration repairs after a non-browser PID reused the lock"
close_process
rm -f "$preferences.omarchy-copy-url-repair.bak" "$profile_root/SingletonLock"
pass "migration treats a live non-browser PID as stale"

# Closing the affected profile and confirming the prompt lets the repair
# proceed.
write_stale_preferences
touch "$profile_root/SingletonLock"
cat >"$stub_bin/gum" <<'STUB'
#!/bin/bash
"$CLOSE_BROWSER"
touch "${GUM_CALLED:?}"
exit 0
STUB
cat >"$stub_bin/close-browser" <<'STUB'
#!/bin/bash
rm -f "$HOME/.config/chromium/SingletonLock"
STUB
chmod +x "$stub_bin/gum" "$stub_bin/close-browser"
GUM_CALLED="$test_dir/gum-called" CLOSE_BROWSER="$stub_bin/close-browser" \
  HOME="$home" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >/dev/null 2>&1 ||
  fail "migration proceeds once the profile is closed and the prompt confirmed"
[[ -e $test_dir/gum-called ]] || fail "migration asks before repairing under a running browser"
jq -e --arg pinned "$pinned_id" '.extensions.commands["linux:Alt+Shift+L"].extension == $pinned' "$preferences" >/dev/null ||
  fail "migration repairs after the browser prompt is confirmed"
pass "migration asks to close the browser and repairs on confirmation"
rm -f "$preferences.omarchy-copy-url-repair.bak"

# With the affected profile closed the ghost registration moves to the pinned id.
printf '#!/bin/bash\nexit 1\n' >"$stub_bin/gum"
close_browser
write_stale_preferences
run_migration || fail "migration repairs the shortcut when no browser is running"

jq -e --arg ghost "$ghost_id" --arg pinned "$pinned_id" '
  .extensions.commands["linux:Alt+Shift+L"].extension == $pinned and
  (.extensions.settings | has($ghost) | not) and
  .extensions.settings[$pinned].commands["copy-url"].was_assigned == true
' "$preferences" >/dev/null || fail "migration rebinds the Copy URL shortcut to the pinned extension id"
[[ -f $preferences.omarchy-copy-url-repair.bak ]] ||
  fail "migration backs up preferences before the repair"
pass "migration rebinds the Copy URL shortcut to the pinned extension id"

# A repaired profile has no ghost registration left, so nothing is pending —
# even while that same profile is open.
rm "$preferences.omarchy-copy-url-repair.bak"
repaired_hash=$(sha256sum "$preferences" | cut -d' ' -f1)
open_browser
run_migration || fail "migration reruns cleanly after the repair"
[[ $(sha256sum "$preferences" | cut -d' ' -f1) == "$repaired_hash" && ! -e $preferences.omarchy-copy-url-repair.bak ]] ||
  fail "migration is idempotent after the repair"
pass "migration is idempotent after the repair"
close_browser

# A remapped shortcut keeps the user's chosen key while moving to the pinned id.
jq -n --arg ghost "$ghost_id" '{extensions: {commands: {"linux:Ctrl+Alt+P": {command_name: "copy-url", extension: $ghost, global: false}}, settings: {}}}' >"$preferences"
run_migration || fail "migration repairs remapped shortcuts"
jq -e --arg pinned "$pinned_id" '.extensions.commands["linux:Ctrl+Alt+P"].extension == $pinned' "$preferences" >/dev/null ||
  fail "migration keeps the remapped key while rebinding to the pinned id"
pass "migration keeps remapped shortcut keys"

# When the pinned extension already holds a copy-url binding (the user fixed
# it by hand), the ghost is dropped rather than doubled into a second binding.
jq -n --arg ghost "$ghost_id" --arg pinned "$pinned_id" '{extensions: {commands: {"linux:Ctrl+Alt+P": {command_name: "copy-url", extension: $pinned, global: false}, "linux:Alt+Shift+L": {command_name: "copy-url", extension: $ghost, global: false}}, settings: {}}}' >"$preferences"
run_migration || fail "migration cleans ghosts alongside a manual repair"
jq -e --arg pinned "$pinned_id" '
  (.extensions.commands | has("linux:Alt+Shift+L") | not) and
  .extensions.commands["linux:Ctrl+Alt+P"].extension == $pinned
' "$preferences" >/dev/null || fail "migration drops the ghost instead of double-binding the pinned extension"
pass "migration never double-binds the pinned extension"

# A browser starting mid-repair may write stale Preferences back on exit, so
# the migration must stay pending for a later browser-free run to verify. A
# stub hands the repair call through and opens the profile right after it.
write_stale_preferences
close_browser
rm -f "$preferences.omarchy-copy-url-repair.bak"
cat >"$stub_bin/python3" <<'STUB'
#!/bin/bash
# Called as `python3 -c <script> <preferences> <pinned_id> <check|repair>`, and
# the check calls report a surviving ghost through their exit status.
"${REAL_PYTHON}" "$@"
status=$?
[[ ${5:-} == "repair" ]] && touch "$HOME/.config/chromium/SingletonLock"
exit $status
STUB
chmod +x "$stub_bin/python3"
if HOME="$home" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >/dev/null 2>&1; then
  fail "migration stays pending when a browser starts mid-repair"
fi
jq -e --arg pinned "$pinned_id" '.extensions.commands["linux:Alt+Shift+L"].extension == $pinned' "$preferences" >/dev/null ||
  fail "migration still repairs preferences before deferring on a late browser"
pass "migration stays pending when a browser starts mid-repair"
rm -f "$stub_bin/python3" "$preferences.omarchy-copy-url-repair.bak"
close_browser

# A browser that started and exited mid-repair restores stale Preferences
# before the final profile check; the post-repair file verification catches it.
write_stale_preferences
cp "$preferences" "$test_dir/stale-preferences"
cat >"$stub_bin/python3" <<'STUB'
#!/bin/bash
"${REAL_PYTHON}" "$@"
status=$?
[[ ${5:-} == "repair" ]] && cp "${STALE_PREFERENCES:?}" "${REPAIRED_PREFERENCES:?}"
exit $status
STUB
chmod +x "$stub_bin/python3"
if HOME="$home" PATH="$stub_bin:$PATH" STALE_PREFERENCES="$test_dir/stale-preferences" \
  REPAIRED_PREFERENCES="$preferences" bash -euo pipefail "$migration" >/dev/null 2>&1; then
  fail "migration stays pending when a briefly-lived browser undoes the repair"
fi
pass "migration stays pending when a briefly-lived browser undoes the repair"
rm -f "$stub_bin/python3"
close_browser
write_stale_preferences
run_migration || fail "migration recovers after a reverted repair"
rm -f "$preferences.omarchy-copy-url-repair.bak"

# A repair attempted while the affected profile was open leaves its backup
# behind. A rerun that sees a clean disk while that profile still runs must
# stay pending — the browser can restore the ghost on exit — and only a
# browser-free rerun verifies the repair and completes.
write_stale_preferences
run_migration || fail "repair run before the verification scenario"
[[ -f $preferences.omarchy-copy-url-repair.bak ]] || fail "verification scenario has a repair backup"
touch "$profile_root/SingletonLock"
run_migration && fail "migration must not complete an unverified repair while a browser runs"
pass "migration keeps an unverified repair pending while a browser runs"
close_browser
run_migration || fail "migration completes once the repair is verified with browsers closed"
pass "migration verifies an attempted repair on a browser-free rerun"
rm -f "$preferences.omarchy-copy-url-repair.bak"

# An installed third-party extension with a command that happens to be named
# copy-url keeps its own registration.
jq -n '{extensions: {commands: {"linux:Alt+Shift+L": {command_name: "copy-url", extension: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", global: false}}, settings: {aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa: {path: "/home/user/.config/some-extension", commands: {}}}}}' >"$preferences"
untouched_hash=$(sha256sum "$preferences" | cut -d' ' -f1)
run_migration || fail "migration leaves installed third-party extensions alone"
[[ $(sha256sum "$preferences" | cut -d' ' -f1) == "$untouched_hash" ]] ||
  fail "migration does not steal a third-party copy-url command registration"
pass "migration leaves installed third-party extensions alone"
