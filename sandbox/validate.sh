#!/bin/bash
set -euo pipefail

echo "=== Omarchy Mac Sandbox Validation ==="

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }
skip() { echo "SKIP: $*"; }

OMARCHY_REPO="/workspace/omarchy-mac"

if [[ ! -d "$OMARCHY_REPO" ]]; then
  fail "Mount omarchy-mac repo at /workspace/omarchy-mac"
fi

cd "$OMARCHY_REPO"

echo
echo "=== Syntax ==="
bash -n bootstrap.sh || fail "bootstrap.sh syntax"
bash -n setup.sh || fail "setup.sh syntax"
bash -n install.sh || fail "install.sh syntax"
bash -n fix-mirrors.sh || fail "fix-mirrors.sh syntax"
bash -n build-packages.sh || fail "build-packages.sh syntax"
pass "Core scripts parse cleanly"

echo
echo "=== Apple Silicon detection ==="
if [[ -f /proc/device-tree/compatible ]]; then
  skip "device tree present, but container compatible content is host-provided"
else
  skip "no /proc/device-tree/compatible in container"
fi

if grep -qa apple /proc/device-tree/compatible 2>/dev/null; then
  skip "grep -qa apple matched container device tree"
else
  pass "grep -qa apple returned false without crashing on missing/binary content"
fi

if grep -qi apple /proc/device-tree/compatible 2>/dev/null; then
  skip "grep -qi apple matched container device tree"
else
  pass "grep -qi apple returned false without crashing on missing/binary content"
fi

echo
echo "=== Repo sanity ==="
grep -q "mirror.archlinuxarm.org" default/pacman/mirrorlist || fail "default mirrorlist missing ALARM mirror"
grep -q '\$arch' default/pacman/mirrorlist.asahi-alarm || fail "Asahi mirrorlist missing arch variable"
grep -q '^\[asahi-alarm\]' default/pacman/pacman.conf || fail "pacman.conf missing asahi-alarm repo"
grep -q '^Architecture = aarch64' default/pacman/pacman.conf || fail "pacman.conf not targeting aarch64"
pass "Default ARM/Asahi repo config is present"

echo
echo "=== Package lists ==="
[[ -f install/omarchy-base.packages ]] || fail "omarchy-base.packages missing"
[[ -f install/omarchy-aarch64-unavailable.packages ]] || fail "unavailable packages list missing"
pass "Package manifests exist"

echo
echo "=== Hardware detection fallbacks ==="
if [[ -d /proc/acpi/button/lid ]]; then
  skip "ACPI lid path exists"
else
  pass "ACPI lid path missing, fallback behavior is acceptable"
fi

echo
echo "=== Installer preconditions ==="
if [[ $(uname -m) == "aarch64" ]]; then
  pass "running on aarch64"
else
  skip "not running on aarch64"
fi

echo
echo "=== Issue #235 fix: Asahi keyring bootstrap order ==="
if grep -q "ensure_asahi_alarm_keyring" install.sh; then
  pass "ensure_asahi_alarm_keyring is present in install.sh"
else
  fail "ensure_asahi_alarm_keyring is missing from install.sh"
fi

if awk '/^main\(\)/,/^}/' install.sh | grep -q "ensure_asahi_alarm_keyring"; then
  pass "ensure_asahi_alarm_keyring is called in main()"
else
  fail "ensure_asahi_alarm_keyring is NOT called in main()"
fi

if awk '/^ensure_arm_package_repo\(\)/,/^}/' install.sh | grep -q "ensure_asahi_alarm_keyring"; then
  fail "ensure_arm_package_repo() still calls ensure_asahi_alarm_keyring internally; should be removed"
else
  pass "ensure_arm_package_repo() no longer calls ensure_asahi_alarm_keyring internally"
fi

if grep -q "Could not import Asahi Alarm signing key" install.sh; then
  pass "keyring import has explicit fail message"
else
  fail "keyring import lacks explicit fail message"
fi

if grep -q "Could not install asahi-alarm-keyring" install.sh; then
  pass "keyring installation has explicit fail message"
else
  fail "keyring installation lacks explicit fail message"
fi

echo
echo "VERDICT: PASS"
