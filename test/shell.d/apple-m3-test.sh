#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

installer="$ROOT/bin/omarchy-mac-asahi-install"
all="$ROOT/install/hardware/all.sh"
vulkan="$ROOT/install/hardware/vulkan.sh"
envs="$ROOT/default/hypr/envs.lua"
apple_lua="$ROOT/default/hypr/apple.lua"
pkgbuild="$ROOT/pkgbuilds/linux-asahi-wip/PKGBUILD"

grep -q 'apple/m3.sh' "$all" || fail "the M3 leaf runs during hardware setup"
pass "the M3 leaf runs during hardware setup"

grep -q 'omarchy-hw-apple-soc --gpu' "$vulkan" || fail "vulkan-asahi is gated on a bound GPU driver"
pass "vulkan-asahi is gated on a bound GPU driver"
! grep -q 'grep -qi "apple" /proc/device-tree/compatible' "$vulkan" ||
  fail "vulkan.sh no longer keys vulkan-asahi off the device tree alone"
pass "vulkan.sh no longer keys vulkan-asahi off the device tree alone"

grep -q 'require("default.hypr.apple")' "$envs" || fail "envs.lua loads the Apple session settings"
pass "envs.lua loads the Apple session settings"
grep -q 'AQ_NO_MODIFIERS' "$apple_lua" || fail "apple.lua sets the software-rendering environment"
pass "apple.lua sets the software-rendering environment"
grep -q -- '--gpu' "$apple_lua" || fail "apple.lua asks whether the GPU driver is bound"
pass "apple.lua asks whether the GPU driver is bound"

bash -n "$pkgbuild" || fail "the linux-asahi-wip PKGBUILD parses"
pass "the linux-asahi-wip PKGBUILD parses"
grep -q 'OMARCHY_KERNEL_BRANCH' "$pkgbuild" || fail "the kernel branch is a build-time choice"
pass "the kernel branch is a build-time choice"
! grep -q '^conflicts=' "$pkgbuild" || fail "linux-asahi-wip installs alongside linux-asahi"
pass "linux-asahi-wip installs alongside linux-asahi"

# The macOS installer wrapper: bash 3.2 syntax, and the one thing it does to
# the installer data is add 14.8.3 wherever it is missing.
bash -n "$installer" || fail "omarchy-mac-asahi-install parses"
pass "omarchy-mac-asahi-install parses"
! grep -qE '\$\{[a-z_]+,,\}|declare -A' "$installer" ||
  fail "omarchy-mac-asahi-install stays within macOS bash 3.2"
pass "omarchy-mac-asahi-install stays within macOS bash 3.2"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

cat >"$test_tmp/data.json" <<'JSON'
{
    "os_list": [
        {
            "name": "Asahi Alarm Minimal (BTRFS)",
            "supported_fw": [
                "12.3",
                "12.3.1",
                "13.5"
            ],
            "package": "https://asahi-alarm.org/asahi-base-btrfs.zip"
        },
        {
            "name": "one line",
            "supported_fw": ["13.5"]
        },
        {
            "name": "already there",
            "supported_fw": ["13.5", "14.8.3"]
        },
        {
            "name": "empty",
            "supported_fw": []
        },
        {
            "name": "Tethered boot (m1n1, for development)",
            "supported_fw": null
        }
    ]
}
JSON

# shellcheck source=/dev/null
source "$installer"
patch_installer_data "$test_tmp/data.json" "$test_tmp/out.json"

python3 - "$test_tmp/out.json" <<'PY' || fail "the patched installer data is what the installer needs"
import json, sys
d = json.load(open(sys.argv[1]))
fw = {o["name"]: o.get("supported_fw") for o in d["os_list"]}
assert fw["Asahi Alarm Minimal (BTRFS)"] == ["14.8.3", "12.3", "12.3.1", "13.5"], fw
assert fw["one line"] == ["13.5", "14.8.3"], fw
assert fw["already there"] == ["13.5", "14.8.3"], fw
assert fw["empty"] == ["14.8.3"], fw
assert fw["Tethered boot (m1n1, for development)"] is None, fw
PY
pass "the patched installer data is what the installer needs"

patch_installer_data "$test_tmp/out.json" "$test_tmp/twice.json"
cmp -s "$test_tmp/out.json" "$test_tmp/twice.json" || fail "patching is idempotent"
pass "patching is idempotent"

[[ $(mac_generation_for j516sap) == "m3" ]] || fail "J516s is an M3 Pro"
pass "J516s is an M3 Pro"
[[ $(mac_generation_for j316sap) == "m1" ]] || fail "J316s is an M1 Pro"
pass "J316s is an M1 Pro"
[[ $(mac_generation_for j999ap) == "unknown" ]] || fail "an unlisted target is unknown"
pass "an unlisted target is unknown"
