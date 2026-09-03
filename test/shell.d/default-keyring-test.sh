#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
keyring_dir="$home/.local/share/keyrings"
keyring_file="$keyring_dir/Default_keyring.keyring"
default_file="$keyring_dir/default"
mkdir -p "$home"

run_default_keyring() {
  HOME="$home" bash -eE -c 'source "$1"' bash "$ROOT/install/user/default-keyring.sh"
}

file_mode() {
  if stat -c %a "$1" 2>/dev/null; then
    return 0
  fi

  stat -f %Lp "$1"
}

grep -qF 'source "$OMARCHY_INSTALL/user/all.sh"' "$ROOT/bin/omarchy-provision-user" ||
  fail "user finalization runs the per-user install stage"
grep -qF 'run_logged "$OMARCHY_INSTALL/user/default-keyring.sh"' "$ROOT/install/user/all.sh" ||
  fail "the per-user install stage runs default-keyring.sh"
pass "user finalization wires the default keyring setup"

run_default_keyring

[[ -d $keyring_dir ]] || fail "default keyring creates its directory"
[[ -f $keyring_file ]] || fail "default keyring creates its keyring file"
[[ -f $default_file ]] || fail "default keyring creates its selector file"
[[ $(file_mode "$keyring_dir") == "700" ]] || fail "default keyring directory is private"
[[ $(file_mode "$keyring_file") == "600" ]] || fail "default keyring file is private"
[[ $(file_mode "$default_file") == "644" ]] || fail "default keyring selector has the expected mode"
grep -qxF '[keyring]' "$keyring_file" || fail "default keyring writes the keyring section"
grep -qxF 'display-name=Default keyring' "$keyring_file" || fail "default keyring writes its display name"
grep -Eq '^ctime=[0-9]+$' "$keyring_file" || fail "default keyring writes a creation time"
grep -qxF 'lock-on-idle=false' "$keyring_file" || fail "default keyring does not lock on idle"
grep -qxF 'lock-after=false' "$keyring_file" || fail "default keyring does not lock after a timeout"
[[ $(<"$default_file") == "Default_keyring" ]] || fail "default keyring selector points at the default keyring"
pass "default keyring creates passwordless-compatible files with safe modes"

keyring_before=$(<"$keyring_file")
default_before=$(<"$default_file")
run_default_keyring
[[ $(<"$keyring_file") == "$keyring_before" ]] || fail "default keyring setup is idempotent"
[[ $(<"$default_file") == "$default_before" ]] || fail "default keyring selector setup is idempotent"
pass "default keyring setup is idempotent"

printf '%s\n' '[custom-keyring]' >"$keyring_file"
printf '%s\n' 'Custom' >"$default_file"
chmod 644 "$keyring_file" "$default_file"
run_default_keyring
[[ $(<"$keyring_file") == "[custom-keyring]" ]] || fail "default keyring setup preserves an existing keyring"
[[ $(<"$default_file") == "Custom" ]] || fail "default keyring setup preserves an existing selector"
[[ $(file_mode "$keyring_file") == "600" ]] || fail "default keyring repairs an existing keyring mode"
[[ $(file_mode "$default_file") == "644" ]] || fail "default keyring keeps an existing selector mode"
pass "default keyring setup preserves existing user data"
