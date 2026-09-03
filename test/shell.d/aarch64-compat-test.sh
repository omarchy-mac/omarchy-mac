#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Static checks first: these run on any machine (and in CI on aarch64) and
# assert the repo's aarch64 surface without needing Asahi hardware. The dynamic
# checks at the bottom simulate aarch64 with stubbed commands.

# x86 configs at default/pacman/ must stay byte-compatible with upstream:
# Architecture = auto and the x86 [omarchy] repo. Pinning aarch64 here would
# break every x86 install the moment this tree is merged.
for config in "$ROOT"/default/pacman/pacman*.conf; do
  grep -qF 'Architecture = auto' "$config" ||
    fail "x86 pacman configs keep Architecture = auto" "missing in: $(basename "$config")"
  grep -qF '[omarchy]' "$config" ||
    fail "x86 pacman configs offer the upstream [omarchy] repo" "missing in: $(basename "$config")"
  grep -qF 'pkgs.omarchy.org' "$config" ||
    fail "x86 pacman configs point at pkgs.omarchy.org" "missing in: $(basename "$config")"
  grep -qF 'Architecture = aarch64' "$config" &&
    fail "x86 pacman configs must not pin aarch64" "pinned in: $(basename "$config")"
  grep -qF '[omarchy-aarch64]' "$config" &&
    fail "x86 pacman configs must not offer the ARM repo" "in: $(basename "$config")"
done
pass "x86 pacman configs match upstream"

# aarch64 configs live under default/pacman/aarch64/ so they cannot leak into
# an x86 refresh. They pin aarch64, offer [omarchy-aarch64], and never point
# at the x86-only pkgs.omarchy.org repo.
for config in "$ROOT"/default/pacman/aarch64/pacman*.conf; do
  grep -qF 'Architecture = aarch64' "$config" ||
    fail "every aarch64 pacman config pins aarch64" "missing in: $(basename "$config")"
  grep -qF '[omarchy-aarch64]' "$config" ||
    fail "every aarch64 pacman config offers the Omarchy ARM repo" "missing in: $(basename "$config")"
  grep -qF 'pkgs.omarchy.org' "$config" &&
    fail "aarch64 pacman configs must not point at the x86 Omarchy package repo" \
      "still x86: $(basename "$config")"
done
pass "aarch64 pacman configs pin ARM and offer [omarchy-aarch64]"

# ARM mirrorlists stay in the aarch64 tree. The x86 tree is allowed to name
# omarchy.org; the aarch64 tree is not.
leaky=()
while read -r file; do
  [[ -n $file ]] || continue
  leaky+=("${file#"$ROOT"/}")
done < <(grep -l 'omarchy\.org' "$ROOT"/default/pacman/aarch64/mirrorlist* 2>/dev/null || true)
(( ${#leaky[@]} == 0 )) ||
  fail "no aarch64 mirrorlist points at an x86 Omarchy mirror" "still x86: ${leaky[*]}"
pass "no aarch64 mirrorlist points at an x86 Omarchy mirror"

# refresh-pacman selects the tree from omarchy-hw-aarch64 rather than shipping
# a single aarch64-only pacman.conf.
grep -qF 'omarchy-hw-aarch64' "$ROOT/bin/omarchy-refresh-pacman" ||
  fail "omarchy-refresh-pacman selects the pacman tree by architecture"
pass "omarchy-refresh-pacman selects the pacman tree by architecture"

# Paths must derive from OMARCHY_PATH (AGENTS.md); a hardcoded HOME breaks once
# the checkout is wired to /usr/share/omarchy.
if grep -qF '$HOME/.local/share/omarchy' "$ROOT/bin/omarchy-refresh-pacman-mirrorlist"; then
  fail "the mirrorlist refresh derives its source from OMARCHY_PATH, not HOME"
fi
pass "the mirrorlist refresh derives its source from OMARCHY_PATH"

# The upstream x86 upgrade rewrites /etc/pacman.d/mirrorlist to x86 mirrors and
# must refuse to run on Apple Silicon (the inverse of the guard in
# omarchy-upgrade-to-quattro-mac). It is not safe to execute here — it writes
# /etc through sudo — so assert the guard statically instead.
grep -qE 'omarchy-hw-aarch64|uname -m' "$ROOT/bin/omarchy-upgrade-to-quattro" &&
  grep -qF 'aarch64' "$ROOT/bin/omarchy-upgrade-to-quattro" ||
  fail "the upstream x86 upgrade fences itself off on Apple Silicon"
pass "the upstream x86 upgrade fences itself off on Apple Silicon"

# --- Simulated aarch64 environment ------------------------------------------

# The Mac fork's safety net: omarchy-pkg-add must skip a package the Arch ARM
# repos do not serve, instead of passing it to pacman and failing the whole
# transaction. Simulate pacman -Q/-Si/-S with a stub; only the ARM package
# "exists" in the fake repos.
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

write_stub() {
  local name="$1"
  local body="$2"

  cat >"$stub_bin/$name" <<<"$body"
  chmod +x "$stub_bin/$name"
}

# -Q answers "installed" only after a -S has installed the package (the helper
# re-checks with -Q after installing), and only for the one package that exists.
write_stub pacman '#!/bin/bash
case "$1" in
  -Q)
    if [[ $2 == "$ARM_ONLY_PKG" ]]; then
      [[ -f $PKG_TEST_STATE ]] && exit 0
      touch "$PKG_TEST_STATE"
    fi
    exit 1
    ;;
  -Si)
    if [[ $2 == "$ARM_ONLY_PKG" ]]; then
      echo "Repository : extra"
      echo "Name        : $2"
      exit 0
    fi
    exit 1
    ;;
  -S)
    printf "pacman -S %s\n" "$*" >>"$PKG_TEST_LOG"
    ;;
  *) exit 1 ;;
esac
'

write_stub omarchy-pkg-missing '#!/bin/bash
exit 0
'

write_stub sudo '#!/bin/bash
"$@"
'

write_stub omarchy-hw-aarch64 '#!/bin/bash
exit 0
'

ARM_ONLY_PKG="ripgrep" \
  PKG_TEST_STATE="$test_tmp/installed" \
  PKG_TEST_LOG="$test_tmp/install.log" \
  PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-pkg-add" ripgrep lib32-nvidia-utils >/dev/null 2>"$test_tmp/skip.log"

grep -qF "Skipping 'lib32-nvidia-utils'" "$test_tmp/skip.log" ||
  fail "the package helper skips packages the repos do not serve" "$(cat "$test_tmp/skip.log")"
grep -qF 'ripgrep' "$test_tmp/install.log" ||
  fail "the package helper installs the available package" "$(cat "$test_tmp/install.log")"
! grep -qF 'lib32-nvidia-utils' "$test_tmp/install.log" ||
  fail "the package helper never passes an unavailable package to pacman" "$(cat "$test_tmp/install.log")"
pass "the package helper skips x86-only packages instead of failing the install"

# On x86 the filter is off: a missing package is passed to pacman and the
# helper fails, matching upstream omarchy-pkg-add.
write_stub omarchy-hw-aarch64 '#!/bin/bash
exit 1
'
rm -f "$test_tmp/installed" "$test_tmp/install.log" "$test_tmp/skip.log"
set +e
ARM_ONLY_PKG="ripgrep" \
  PKG_TEST_STATE="$test_tmp/installed" \
  PKG_TEST_LOG="$test_tmp/install.log" \
  PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-pkg-add" ripgrep lib32-nvidia-utils >/dev/null 2>"$test_tmp/skip.log"
x86_status=$?
set -e
(( x86_status != 0 )) || fail "x86 pkg-add fails when a package is missing"
! grep -qF "Skipping 'lib32-nvidia-utils'" "$test_tmp/skip.log" ||
  fail "x86 pkg-add does not skip missing packages" "$(cat "$test_tmp/skip.log")"
grep -qF 'lib32-nvidia-utils' "$test_tmp/install.log" ||
  fail "x86 pkg-add passes the missing package to pacman" "$(cat "$test_tmp/install.log")"
pass "x86 pkg-add fails on missing packages, matching upstream"

