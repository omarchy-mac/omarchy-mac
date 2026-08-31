echo "Drive keyboard backlight from the ambient light sensor"

# Existing installs never run first-run again, so they would keep a dark
# keyboard in a dark room until someone discovered Shift+F1. Copy the unit
# into the user systemd dir (the settings package may not ship it yet) and
# enable it. ExecCondition makes this a no-op on machines with no ALS or
# no keyboard backlight LED.

unit_src="$OMARCHY_PATH/default/systemd/user/omarchy-brightness-keyboard-auto.service"
unit_dst="$HOME/.config/systemd/user/omarchy-brightness-keyboard-auto.service"

if [[ -f $unit_src ]]; then
  mkdir -p "$HOME/.config/systemd/user"
  cp "$unit_src" "$unit_dst"
fi

systemctl --user daemon-reload >/dev/null 2>&1 || true

if ! systemctl --user enable omarchy-brightness-keyboard-auto.service >/dev/null 2>&1; then
  wants_dir="$HOME/.config/systemd/user/graphical-session.target.wants"
  mkdir -p "$wants_dir"
  if [[ -f $unit_dst ]]; then
    ln -sfn "$unit_dst" "$wants_dir/omarchy-brightness-keyboard-auto.service"
  elif [[ -f /usr/lib/systemd/user/omarchy-brightness-keyboard-auto.service ]]; then
    ln -sfn /usr/lib/systemd/user/omarchy-brightness-keyboard-auto.service \
      "$wants_dir/omarchy-brightness-keyboard-auto.service"
  fi
fi

if systemctl --user is-active --quiet graphical-session.target; then
  systemctl --user start omarchy-brightness-keyboard-auto.service >/dev/null 2>&1 || true
fi
