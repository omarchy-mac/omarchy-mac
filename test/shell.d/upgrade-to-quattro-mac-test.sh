#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

upgrade_to_quattro_mac="$ROOT/bin/omarchy-upgrade-to-quattro-mac"

function_body() {
  awk -v name="$1" '$0 == name "() {" { inside = 1; next } inside && $0 == "}" { exit } inside' "$upgrade_to_quattro_mac"
}

# Quattro renamed the setup entry points, and set -e turns a call to a command
# that no longer ships into a half-finished upgrade: the checkout, the system
# symlinks, and the Hyprland config are already replaced by the time this runs.
# Scoped to the function body so the retired package names stay out of it.
setup_body=$(function_body run_quattro_setup)
[[ -n $setup_body ]] || fail "the Mac Quattro upgrade has a run_quattro_setup step"
while read -r command_name; do
  [[ -n $command_name ]] || continue
  [[ -x "$ROOT/bin/$command_name" ]] ||
    fail "Mac Quattro upgrade only calls setup commands that ship in bin/" "missing: $command_name"
done < <(grep -oE '\bomarchy-[a-z0-9-]+' <<<"$setup_body" | sort -u)
pass "Mac Quattro upgrade only calls setup commands that ship in bin/"

grep -F 'sudo omarchy-apply-system --install-user "$USER" --upgrade' "$upgrade_to_quattro_mac" >/dev/null ||
  fail "Mac Quattro upgrade applies system setup as root"
grep -F 'omarchy-provision-user --force' "$upgrade_to_quattro_mac" >/dev/null ||
  fail "Mac Quattro upgrade finalizes the user without sudo"
pass "Mac Quattro upgrade runs system setup as root and user setup as the user"

# Naming them keeps the 3.x spellings from creeping back in a later merge.
if grep -qE 'omarchy-setup-system|omarchy-finalize-user' "$upgrade_to_quattro_mac"; then
  fail "Mac Quattro upgrade does not call the retired 3.x command names"
fi
pass "Mac Quattro upgrade does not call the retired 3.x command names"

# Issue #200: the ref used to default to main, so a no-argument run checked out
# 3.8.2, installed packages against it, and aborted mid-upgrade on the first
# missing Quattro file — leaving the machine half-migrated.
grep -F 'upgrade_ref="${OMARCHY_UPGRADE_REF:-quattro}"' "$upgrade_to_quattro_mac" >/dev/null ||
  fail "Mac Quattro upgrade defaults to the quattro ref" "expected: upgrade_ref=\"\${OMARCHY_UPGRADE_REF:-quattro}\""
pass "Mac Quattro upgrade defaults to the quattro ref"

validate_body=$(function_body validate_quattro_tree)
[[ -n $validate_body ]] || fail "the Mac Quattro upgrade validates the selected tree"

# The validator must run after the checkout switch but before packages are
# installed or anything under /usr and /etc is written.
main_body=$(function_body main)
[[ $main_body == *install_quattro_packages* ]] ||
  fail "main still installs the Quattro package set"
steps_before_install=${main_body%%install_quattro_packages*}
[[ $steps_before_install == *switch_checkout_to_quattro* && $steps_before_install == *validate_quattro_tree* ]] ||
  fail "the tree validator runs before any package or system changes"
pass "the tree validator runs before any package or system changes"

# Exercise the validator itself against fake trees: a 3.x tree must be rejected,
# a Quattro-shaped one accepted. The function reads $checkout/$upgrade_ref and
# reports through fail(), so stub that out for the extraction run.
check_tree() {
  local tree_version="$1" description="$2" expect="$3" drop_path="${4:-}" status workdir

  workdir=$(mktemp -d)
  mkdir -p "$workdir/bin" "$workdir/etc/profile.d" "$workdir/default/uwsm/env.d" \
    "$workdir/default/environment.d" "$workdir/install"
  printf '%s\n' "$tree_version" >"$workdir/version"
  : >"$workdir/etc/profile.d/omarchy.sh"
  : >"$workdir/default/uwsm/env.d/10-omarchy"
  : >"$workdir/default/environment.d/10-omarchy-fcitx.conf"
  : >"$workdir/install/omarchy-base.packages"
  printf '#!/bin/bash\n' >"$workdir/bin/omarchy-apply-system"
  printf '#!/bin/bash\n' >"$workdir/bin/omarchy-provision-user"
  chmod +x "$workdir/bin/omarchy-apply-system" "$workdir/bin/omarchy-provision-user"
  [[ -z $drop_path ]] || rm -f "$workdir/$drop_path"

  status=0
  (
    checkout=$workdir
    upgrade_ref=quattro
    log() { :; }
    fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
    # function_body hands back the bare body; re-wrap it into a definition.
    eval "validate_quattro_tree() {
$validate_body
}"
    validate_quattro_tree
  ) >/dev/null 2>&1 || status=$?
  rm -rf "$workdir"

  if [[ $expect == "reject" && $status == 0 ]]; then
    fail "the tree validator rejects a non-Quattro tree ($description)"
  elif [[ $expect == "accept" && $status != 0 ]]; then
    fail "the tree validator accepts a Quattro tree ($description)" "exit status: $status"
  fi
}

check_tree "3.8.2" "version 3.8.2" reject
# The failure #200 reported: a 4.x-shaped version is not enough on its own.
check_tree "4.0.0.alpha" "missing etc/profile.d/omarchy.sh" reject "etc/profile.d/omarchy.sh"
check_tree "4.0.0.alpha" "version 4.0.0.alpha" accept
pass "the tree validator only lets Quattro trees through"

# The curl one-liner is written out in both the script and the guide, so a
# branch rename can leave a 3.x user fetching an upgrade that no longer exists.
script_url=$(grep -oE 'https://[^ ]*omarchy-upgrade-to-quattro-mac' "$upgrade_to_quattro_mac" | head -1)
doc_url=$(grep -oE 'https://[^ ]*omarchy-upgrade-to-quattro-mac' "$ROOT/docs/upgrade-to-quattro.md" | head -1)
[[ -n $script_url && -n $doc_url ]] || fail "the upgrade one-liner appears in both the script and the guide"
[[ $script_url == "$doc_url" ]] ||
  fail "the upgrade one-liner agrees between script and guide" "script: $script_url
doc:    $doc_url"
pass "the upgrade one-liner agrees between the script and the guide"

# Issue #208: the package pass attempted every name in the default set, so a 3.x
# machine spent hours on AUR builds install.sh deliberately skips -- and one of
# them, quickshell-git, fails outright on the pre-upgrade GL stack.
install_body=$(function_body install_quattro_packages)
[[ -n $install_body ]] || fail "the Mac Quattro upgrade has an install_quattro_packages step"

# Naming the matcher proves nothing: without the load the list is empty and the
# filter answers no to everything. Pin the call, its order, and the override.
install_code=$(grep -vE '^[[:space:]]*#' <<<"$install_body")
[[ $install_code == *load_unavailable_packages* ]] ||
  fail "the package pass loads the aarch64 unavailable list"
[[ ${install_code%%while read*} == *load_unavailable_packages* ]] ||
  fail "the unavailable list is loaded before the package loop reads it"
grep -qF '${OMARCHY_TRY_UNAVAILABLE:-0} != "1" ]] && package_is_unavailable_here' <<<"$install_code" ||
  fail "the filter runs on the loop and stays overridable with OMARCHY_TRY_UNAVAILABLE"
pass "the upgrade filters the package set through the aarch64 unavailable list"

# Exercise the matcher against a list on disk rather than trust its name.
matcher_probe=$(mktemp -d)
mkdir -p "$matcher_probe/install"
printf '# a comment\n\nlisted-package\n' >"$matcher_probe/install/omarchy-aarch64-unavailable.packages"
(
  checkout="$matcher_probe"
  eval "$(awk '/^load_unavailable_packages\(\) \{/,/^\}/' "$upgrade_to_quattro_mac")"
  eval "$(awk '/^package_is_unavailable_here\(\) \{/,/^\}/' "$upgrade_to_quattro_mac")"
  load_unavailable_packages
  package_is_unavailable_here listed-package || exit 1
  ! package_is_unavailable_here some-other-package || exit 1
) || fail "the unavailable matcher answers from the list on disk"
rm -rf "$matcher_probe"
pass "the unavailable matcher answers from the list on disk"

# Skipping quickshell-git is only safe where something else provides Quickshell.
# A packaged install gets it from the omarchy package; this layout installs no
# such package, so state the invariant rather than one spelling of it.
quickshell_git_skipped=0
if grep -qxF 'quickshell-git' "$ROOT/install/omarchy-aarch64-unavailable.packages"; then
  quickshell_git_skipped=1
fi
installs_quickshell=0
if grep -qE '^[[:space:]]*yay -S .*[[:space:]]quickshell([[:space:]]|$)' <<<"$install_code"; then
  installs_quickshell=1
fi
(( ! quickshell_git_skipped || installs_quickshell )) ||
  fail "quickshell-git is skipped and nothing installs quickshell: the upgrade leaves no shell"
pass "the upgrade always ends up with Quickshell installed"

# Every other fatal step reports through fail(); a bare set -e abort here would
# die silently after the checkout has already been switched.
if (( installs_quickshell )); then
  grep -A1 -E '^[[:space:]]*yay -S .*[[:space:]]quickshell([[:space:]]|$)' <<<"$install_code" |
    grep -qF 'fail "' ||
    fail "a failed quickshell install reports through fail(), not a silent set -e abort"
  pass "a failed quickshell install reports through fail()"
fi

# Issue #235: a machine put together on a generic aarch64 base carries the
# [asahi-alarm] stanza without its signing keyring, and pacman will not create
# that database until the master key is trusted. install.sh bootstraps the key
# before it refreshes; the upgrade refreshes the same databases, so it needs the
# same bootstrap or the Quattro package pass fails with a missing database and
# never names the key as the cause.
keyring_body=$(function_body ensure_asahi_alarm_keyring)
[[ -n $keyring_body ]] || fail "the Mac Quattro upgrade bootstraps the Asahi Alarm keyring"

grep -qF 'pacman-key --recv-keys "$asahi_alarm_key"' <<<"$keyring_body" ||
  fail "the upgrade bootstraps the Asahi Alarm package signing key"
grep -qF 'pacman-key --lsign-key "$asahi_alarm_key"' <<<"$keyring_body" ||
  fail "the upgrade locally trusts the Asahi Alarm package signing key"
grep -qF 'pacman -Sy --needed --noconfirm asahi-alarm-keyring' <<<"$keyring_body" ||
  fail "the upgrade installs the Asahi Alarm package keyring"

# Trusting the key after the refresh it exists to unblock would fix nothing.
keyring_call=$(grep -n '^  ensure_asahi_alarm_keyring$' "$upgrade_to_quattro_mac" | cut -d: -f1)
refresh_call=$(grep -n 'pacman -Sy --noconfirm' "$upgrade_to_quattro_mac" | grep -v -- '--needed' |
  head -1 | cut -d: -f1)
[[ -n $keyring_call && -n $refresh_call ]] ||
  fail "the upgrade bootstraps the Asahi keyring before refreshing package databases"
(( keyring_call < refresh_call )) ||
  fail "the Asahi keyring is trusted before the package database refresh"

# Two copies of the same bootstrap, because the upgrade is self-contained and
# cannot source the installer. The fingerprint is the one part that turns silent
# if it drifts, so pin them to each other rather than to a literal here.
install_key=$(grep -oE 'asahi_alarm_key="[0-9A-F]+"' "$ROOT/install.sh" | head -1)
upgrade_key=$(grep -oE 'asahi_alarm_key="[0-9A-F]+"' "$upgrade_to_quattro_mac" | head -1)
[[ -n $install_key ]] || fail "install.sh pins the Asahi Alarm signing key"
[[ $upgrade_key == "$install_key" ]] ||
  fail "the upgrade pins the same Asahi Alarm signing key as install.sh" "installer: $install_key
upgrade:   $upgrade_key"
pass "the Quattro upgrade trusts the Asahi Alarm signing key before refreshing"

# Both early exits matter: a machine without the stanza has nothing to trust,
# and one that already has the keyring must not be sent to a keyserver on every
# upgrade. Run the function against stubs rather than read its guards.
keyring_probe=$(mktemp -d)
mkdir -p "$keyring_probe/bin"
cat >"$keyring_probe/bin/grep" <<'SH'
#!/bin/bash
exit "${STUB_STANZA_PRESENT:-0}"
SH
cat >"$keyring_probe/bin/pacman" <<'SH'
#!/bin/bash
if [[ $1 == "-Q" ]]; then
  exit "${STUB_KEYRING_INSTALLED:-0}"
fi
printf 'pacman %s\n' "$*" >>"$STUB_LOG"
SH
cat >"$keyring_probe/bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$STUB_LOG"
# An untrusted key: --list-keys fails, so the import path has to run.
[[ $1 == "pacman-key" && $2 == "--list-keys" ]] && exit 1
exit 0
SH
chmod +x "$keyring_probe/bin/grep" "$keyring_probe/bin/pacman" "$keyring_probe/bin/sudo"

run_keyring_bootstrap() {
  (
    export PATH="$keyring_probe/bin:$PATH"
    export STUB_LOG="$keyring_probe/calls" STUB_STANZA_PRESENT="$1" STUB_KEYRING_INSTALLED="$2"
    : >"$STUB_LOG"
    log() { :; }
    asahi_alarm_key="probe-key"
    eval "$(awk '/^ensure_asahi_alarm_keyring\(\) \{/,/^\}/' "$upgrade_to_quattro_mac")"
    ensure_asahi_alarm_keyring
  )
  cat "$keyring_probe/calls"
}

calls=$(run_keyring_bootstrap 1 0)
[[ -z $calls ]] ||
  fail "no Asahi repo stanza means nothing to bootstrap" "$calls"

calls=$(run_keyring_bootstrap 0 0)
[[ -z $calls ]] ||
  fail "an installed asahi-alarm-keyring is left alone" "$calls"

calls=$(run_keyring_bootstrap 0 1)
grep -qF 'pacman-key --recv-keys probe-key' <<<"$calls" ||
  fail "a missing keyring imports the signing key" "$calls"
grep -qF 'pacman-key --lsign-key probe-key' <<<"$calls" ||
  fail "a missing keyring locally signs the imported key" "$calls"
grep -qF 'pacman -Sy --needed --noconfirm asahi-alarm-keyring' <<<"$calls" ||
  fail "a missing keyring is installed from the repo" "$calls"
rm -rf "$keyring_probe"
pass "the keyring bootstrap runs only where it is needed"
