#!/bin/bash

# Enable AND start the user systemd units we ship. Runs at first-run rather
# than at finalize-user time because the user manager isn't live during the
# ISO chroot — by first-run, the Hyprland/uwsm session is up and
# `systemctl --user enable --now` both writes the correct .wants symlinks
# (based on each unit's [Install]/WantedBy) and starts the services so the
# first session has bluetooth pairing, sleep lock, etc. live immediately
# instead of waiting for the next login. ConditionPath* in the unit files
# keep the enabled units inert on hardware they don't apply to.

set -euo pipefail

# The ALS keyboard-backlight unit lives in the Omarchy tree. Copy it into the
# user systemd dir so enable works before omarchy-settings ships it under
# /usr/lib/systemd/user/.
als_kbd_unit="${OMARCHY_PATH:-/usr/share/omarchy}/default/systemd/user/omarchy-brightness-keyboard-auto.service"
if [[ -f $als_kbd_unit ]]; then
  mkdir -p "$HOME/.config/systemd/user"
  cp "$als_kbd_unit" "$HOME/.config/systemd/user/omarchy-brightness-keyboard-auto.service"
fi

systemctl --user daemon-reload
systemctl --user enable --now \
  bt-agent.service \
  omarchy-recover-internal-monitor.service \
  omarchy-sleep-lock.service \
  omarchy-migrate-notify.service \
  omarchy-fcitx5.service \
  omarchy-crash-watch.service \
  omarchy-brightness-keyboard-auto.service
