#!/bin/bash

# The Broadcom firmware on Apple Silicon Macs wedges across s2idle: scans fail
# with -52 and every association is rejected with status_code=16, which
# NetworkManager reports as a wrong password. Only a driver reload clears it.
# Upstream: https://github.com/AsahiLinux/linux/issues/439
#
# Reload after resume, but only when the wedge signature actually appears, so
# this is a no-op once the firmware bug is fixed.
#
# Logs: journalctl -u omarchy-wifi-resume-fix

if [[ $(uname -m) == "aarch64" ]] &&
  lspci -nn | grep -E '14e4:(4425|4433)' >/dev/null; then
  echo "Detected Apple Silicon Broadcom Wi-Fi; installing resume recovery"

  cat > /usr/local/bin/omarchy-wifi-resume-fix <<'SCRIPT'
#!/bin/sh
WAIT_BEFORE=12    # backstop: reload anyway if wifi is still not up after this
WAIT_AFTER=30     # seconds to wait for reconnect after a reload
REJECTS=2         # ASSOC-REJECT status_code=16 events that confirm a wedge
START=$(date '+%Y-%m-%d %H:%M:%S')
wedged() {
    journal_output=$(journalctl --since "$START" -t wpa_supplicant --no-pager 2>/dev/null || true)
    if [ -z "$journal_output" ]; then
      journal_output=$(journalctl -t wpa_supplicant --no-pager 2>/dev/null | tail -n 200 || true)
    fi
    n=$(printf '%s\n' "$journal_output" | grep -c 'CTRL-EVENT-ASSOC-REJECT.*status_code=16')
    [ "${n:-0}" -ge "$REJECTS" ]
}
wifi_iface() {
    nmcli -t -f DEVICE,TYPE device status 2>/dev/null |
        awk -F: '$2 == "wifi" { print $1; exit }'
}
wifi_state() {
    nmcli -t -f DEVICE,STATE device status 2>/dev/null |
        awk -F: -v d="$1" '$1 == d { print $2; exit }'
}
if [ "$(nmcli radio wifi 2>/dev/null)" = "disabled" ]; then
    echo "wifi radio is disabled, nothing to do"
    exit 0
fi
for cmd in nmcli journalctl modprobe; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "missing $cmd"; exit 1; }
done
IFACE=$(wifi_iface)
: "${IFACE:=wlan0}"
i=0
while [ "$i" -lt "$WAIT_BEFORE" ]; do
    state=$(wifi_state "$IFACE")
    if [ "$state" = "connected" ]; then
        echo "wifi back after ${i}s on $IFACE - no reload needed"
        exit 0
    fi
    if wedged; then
        echo "wedged firmware confirmed after ${i}s (iface=$IFACE state=${state:-none}) - reloading brcmfmac"
        break
    fi
    i=$((i + 1))
    sleep 1
done
if [ "$i" -ge "$WAIT_BEFORE" ]; then
    echo "wifi not back after ${WAIT_BEFORE}s (iface=$IFACE state=${state:-none}) - reloading brcmfmac"
fi
modprobe -r brcmfmac_wcc brcmfmac || { echo "failed to unload brcmfmac"; exit 1; }
sleep 1
modprobe brcmfmac || { echo "failed to reload brcmfmac"; exit 1; }
echo "brcmfmac reloaded, waiting for NetworkManager to reconnect"
i=0
while [ "$i" -lt "$WAIT_AFTER" ]; do
    IFACE=$(wifi_iface)
    : "${IFACE:=wlan0}"
    state=$(wifi_state "$IFACE")
    if [ "$state" = "connected" ]; then
        echo "reconnected ${i}s after reload on $IFACE"
        exit 0
    fi
    i=$((i + 1))
    sleep 1
done
echo "still not connected ${WAIT_AFTER}s after reload (iface=$IFACE state=${state:-none})"
exit 1
SCRIPT
  chmod 755 /usr/local/bin/omarchy-wifi-resume-fix

  cat > /etc/systemd/system/omarchy-wifi-resume-fix.service <<'EOF'
[Unit]
Description=Omarchy Wi-Fi Resume Fix for Apple Silicon Macs
After=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
After=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/omarchy-wifi-resume-fix
TimeoutStartSec=120

[Install]
WantedBy=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
EOF

  systemctl enable omarchy-wifi-resume-fix.service
fi
