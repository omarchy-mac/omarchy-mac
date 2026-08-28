echo "Retire the Asahi bootstrap account from wheel when a different owner is already an administrator"

# Asahi Alarm's image uses alarm as its bootstrap administrator. Guided setup
# now removes it from wheel once a permanent owner has sudo, but that change
# was force-pushed off quattro and only restored later. Installs from the gap
# still have alarm in wheel; polkit then authenticates the bootstrap account
# instead of the owner. Locking alarm does not help: the agent still picks it.

[[ $(uname -m) == "aarch64" ]] || exit 0
[[ $(id -un) != "alarm" ]] || exit 0
id -u alarm >/dev/null 2>&1 || exit 0

user_in_group() {
  local user="$1" group="$2"
  id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -qx "$group"
}

user_in_group alarm wheel || exit 0

# Do not demote alarm if that would leave wheel with no other member. The
# installer refuses the same handoff until the permanent owner is in wheel.
other_admins=0
wheel_members=$(getent group wheel | cut -d: -f4)
IFS=',' read -ra members <<<"$wheel_members"
for member in "${members[@]}"; do
  if [[ -n $member && $member != "alarm" ]]; then
    other_admins=1
    break
  fi
done
(( other_admins )) || exit 0

sudo gpasswd -d alarm wheel >/dev/null
