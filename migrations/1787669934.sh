echo "Ensure zram-generator is installed for configured zram swap"

if omarchy-pkg-missing zram-generator; then
  omarchy-pkg-add zram-generator
fi

if systemctl is-active --quiet dev-zram0.swap; then
  exit 0
fi

# Installing the package after boot does not run the generated unit until the
# manager reloads. Start it now so upgraded machines get the same zram device a
# fresh install gets on its next boot.
sudo systemctl daemon-reload
sudo systemctl start systemd-zram-setup@zram0.service
