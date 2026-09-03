#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

export HOME="$test_tmp/home"
mkdir -p "$HOME/.local/share/Steam/steamui" "$HOME/.local/share/applications"

unpatched='prefix const t=(0,B.Dp)("System.Network.RegisterForDeviceChanges");t&&SteamClient.System.Network.RegisterForDeviceChanges(this.OnNetworkDevicesChanged),(0,B.Dp)("System.Network.GetProxyInfo")&&SteamClient.System.Network.GetProxyInfo().then(e=>this.m_proxyInfo=e),(0,B.Dp)("System.Network.RegisterForConnectivityTestChanges")&&SteamClient.System.Network.RegisterForConnectivityTestChanges(this.OnConnectivityTestStateChanged),t||(this.m_bIsAwaitingInitialNetworkState=!1) suffix'
printf '%s' "$unpatched" >"$HOME/.local/share/Steam/steamui/chunk~deadbeef.js"

PATH="$ROOT/bin:$PATH" bash "$ROOT/bin/omarchy-launch-steam" --prepare

desktop="$HOME/.local/share/applications/steam.desktop"
if [[ $(uname -m) != aarch64 ]]; then
  [[ ! -f $desktop ]] || fail "prepare is a no-op off aarch64"
  pass "prepare is a no-op off aarch64"
  exit 0
fi

grep -q 'Exec=omarchy-launch-steam' "$desktop" || fail "prepare writes a Steam desktop entry"
pass "prepare writes a Steam desktop entry"

patched=$(<"$HOME/.local/share/Steam/steamui/chunk~deadbeef.js")
[[ $patched == *'typeof SteamClient.System.Network.RegisterForDeviceChanges'* ]] || fail "prepare guards RegisterForDeviceChanges" "$patched"
[[ $patched == *'this.m_bIsAwaitingInitialNetworkState=!1,this.m_bIsConnectedToANetwork=!0'* ]] || fail "prepare clears the waiting-for-network flag"
[[ -f $HOME/.local/share/Steam/steamui/chunk~deadbeef.js.omarchy-bak ]] || fail "prepare backs up the original chunk"
pass "prepare patches the Steam UI network store"

PATH="$ROOT/bin:$PATH" bash "$ROOT/bin/omarchy-launch-steam" --prepare
[[ $(<"$HOME/.local/share/Steam/steamui/chunk~deadbeef.js") == "$patched" ]] || fail "prepare is idempotent"
pass "prepare is idempotent"
