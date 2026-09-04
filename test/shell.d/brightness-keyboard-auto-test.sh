#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
led="$test_tmp/leds/kbd_backlight"
als="$test_tmp/als"
home="$test_tmp/home"
mkdir -p "$mock_bin" "$led" "$home"

echo 255 >"$led/max_brightness"
echo 0 >"$led/brightness"
echo 10 >"$als"

# brightnessctl writes straight into the fake LED.
cat >"$mock_bin/brightnessctl" <<SH
#!/bin/bash
echo "\${@: -1}" >"$led/brightness"
SH
chmod +x "$mock_bin/brightnessctl"

run_auto() {
  HOME="$home" OMARCHY_KEYBOARD_LED="$led" OMARCHY_AMBIENT_LIGHT_SENSOR="$als" \
    PATH="$mock_bin:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-brightness-keyboard-auto" "$@"
}

brightness() { cat "$led/brightness"; }

if HOME="$home" OMARCHY_KEYBOARD_LED="$test_tmp/missing" OMARCHY_AMBIENT_LIGHT_SENSOR="$test_tmp/missing" \
  "$ROOT/bin/omarchy-brightness-keyboard-auto" probe 2>/dev/null; then
  fail "probe fails without the hardware"
fi
pass "probe fails without the hardware"

run_auto probe && pass "probe succeeds with a sensor and LED"

run_auto tick
[[ $(brightness) == "100" ]] || fail "dark room lights the keys at the default level" "got $(brightness)"
pass "dark room lights the keys at the default level"

echo 200 >"$als"
run_auto tick
[[ $(brightness) == "0" ]] || fail "bright room turns the keys off" "got $(brightness)"
pass "bright room turns the keys off"

echo 60 >"$als"
run_auto tick
[[ $(brightness) == "0" ]] || fail "hysteresis keeps the keys off between the thresholds" "got $(brightness)"
pass "hysteresis keeps the keys off between the thresholds"

echo 10 >"$als"
run_auto tick
[[ $(brightness) == "100" ]] || fail "keys come back on below the dark threshold" "got $(brightness)"
pass "keys come back on below the dark threshold"

echo 150 >"$led/brightness"
run_auto tick
[[ $(cat "$home/.local/state/omarchy/keyboard-backlight/preferred") == "150" ]] || fail "a manual change becomes the preferred level"
pass "a manual change becomes the preferred level"

run_auto idle
[[ $(brightness) == "0" ]] || fail "idle turns the keys off" "got $(brightness)"
pass "idle turns the keys off"

run_auto tick
[[ $(brightness) == "0" ]] || fail "ticks keep the keys off while idle" "got $(brightness)"
pass "ticks keep the keys off while idle"

run_auto active
[[ $(brightness) == "150" ]] || fail "resume restores the preferred level" "got $(brightness)"
pass "resume restores the preferred level"

mkdir -p "$home/.config/omarchy"
printf 'DARK_LUX=5\nBRIGHT_LUX=8\nIDLE_SECONDS=30\n' >"$home/.config/omarchy/keyboard-backlight.conf"
run_auto tick
[[ $(brightness) == "0" ]] || fail "config thresholds override the defaults" "got $(brightness)"
pass "config thresholds override the defaults"

[[ $(run_auto status) == *"idle_seconds=30"* ]] || fail "status reports the configured idle seconds"
pass "status reports the configured idle seconds"
