#!/bin/bash
set -euo pipefail

echo "Retire the Asahi bootstrap admin account on installs that predate setup-script fix"

if ! id -u alarm >/dev/null 2>&1; then
  exit 0
fi

owner=$(id -un 1001 2>/dev/null || true)
if [[ ${owner:-} == alarm ]]; then
  exit 0
fi

if ! id -nG alarm 2>/dev/null | tr ' ' '\n' | grep -qx wheel; then
  exit 0
fi

if command -v gpasswd >/dev/null 2>&1; then
  gpasswd -d alarm wheel || true
fi

if getent group wheel | grep -q alarm; then
  echo "Warning: failed to remove alarm from wheel" >&2
  exit 1
fi

echo "Removed alarm from wheel group"