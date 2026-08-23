echo "Install the protected Asahi audio stack on Apple Silicon"

# Fresh installs run this leaf from omarchy-apply-hardware. Reuse it here so
# existing installs get the same hardware gate and package set. The package
# check makes this safe when another user has already repaired the machine.
audio_setup="$OMARCHY_PATH/install/hardware/apple/audio.sh"
[[ -f $audio_setup ]] || exit 0

source "$audio_setup"

# WirePlumber reads the protected graph only at startup, and speakersafetyd is
# activated by udev when the audio device appears. A reboot applies both without
# briefly exposing the raw speakers or disrupting an update in progress.
if (( ${OMARCHY_ASAHI_AUDIO_PACKAGES_CHANGED:-0} )); then
  omarchy-state set reboot-required
fi
