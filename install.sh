#!/bin/bash

# Architecture dispatcher. aarch64 has no Omarchy ISO, so it runs the Apple
# Silicon installer. x86 uses the upstream ISO pipeline when this tree contains
# it; otherwise install from https://omarchy.org/.

set -euo pipefail

readonly checkout="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$checkout/bin:${PATH:-}"

if "$checkout/bin/omarchy-hw-aarch64"; then
  exec bash "$checkout/install/aarch64/install.sh" "$@"
fi

if [[ -f $checkout/install/helpers/all.sh && -f $checkout/install/packaging/all.sh ]]; then
  set -eEo pipefail
  export OMARCHY_PATH="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
  export OMARCHY_INSTALL="$OMARCHY_PATH/install"
  export OMARCHY_INSTALL_LOG_FILE="/var/log/omarchy-install.log"
  export PATH="$OMARCHY_PATH/bin:$PATH"
  source "$OMARCHY_INSTALL/helpers/all.sh"
  source "$OMARCHY_INSTALL/preflight/all.sh"
  source "$OMARCHY_INSTALL/packaging/all.sh"
  source "$OMARCHY_INSTALL/config/all.sh"
  source "$OMARCHY_INSTALL/login/all.sh"
  source "$OMARCHY_INSTALL/post-install/all.sh"
  exit 0
fi

echo "On x86_64, install Omarchy from the ISO: https://omarchy.org/" >&2
echo "This checkout has no ISO installer pipeline; aarch64 uses install/aarch64/install.sh." >&2
exit 1
