# Prefer media keys on Apple-like keyboards, with Fn for F1-F12, the way macOS
# does. The Mac media bindings depend on it: default/hypr/bindings/media.lua
# binds bare XF86MonBrightness* and SHIFT+XF86MonBrightness*, so the top row has
# to emit media keycodes without Fn for display and keyboard brightness to work.
# hid_apple is the Apple keyboard driver. Writing this on a non-Apple x86
# machine is a Mac-fork leak; only Apple Silicon (and T2, which also loads
# hid_apple) should get fnmode=1.
if omarchy-hw-apple-silicon || modinfo hid_apple &>/dev/null; then
  if [[ ! -f /etc/modprobe.d/hid_apple.conf ]]; then
    sudo mkdir -p /etc/modprobe.d
    echo "options hid_apple fnmode=1" | sudo tee /etc/modprobe.d/hid_apple.conf >/dev/null
  fi
fi
