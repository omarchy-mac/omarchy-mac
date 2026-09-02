#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
installed_dir="$test_tmp/installed"
install_log="$test_tmp/install-log"
terminal_log="$test_tmp/terminal-log"
notification_log="$test_tmp/notification-log"
setup_log="$test_tmp/setup-log"
launcher_log="$test_tmp/launcher-log"
browser_file="$test_tmp/browser"
mkdir -p "$mock_bin" "$test_home/.config" "$installed_dir"

cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
[[ ! -e $OMARCHY_TEST_INSTALLED_DIR/$1 ]]
SH

cat >"$mock_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
[[ -e $OMARCHY_TEST_INSTALLED_DIR/$1 ]]
SH

cat >"$mock_bin/omarchy-launch-floating-terminal-with-presentation" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_TERMINAL_LOG"
SH

cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >>"$OMARCHY_TEST_NOTIFICATION_LOG"
SH

cat >"$mock_bin/omarchy-launch-tui" <<'SH'
#!/bin/bash
printf 'tui:%s\n' "$*" >>"$OMARCHY_TEST_LAUNCHER_LOG"
SH

cat >"$mock_bin/omarchy-test-editor" <<'SH'
#!/bin/bash
printf 'inline:%s:%s\n' "${0##*/}" "$*" >>"$OMARCHY_TEST_LAUNCHER_LOG"
SH

cat >"$mock_bin/omarchy-test-setup-call" <<'SH'
#!/bin/bash
printf '%s:%s\n' "${0##*/}" "$*" >>"$OMARCHY_TEST_SETUP_LOG"
[[ ${OMARCHY_TEST_SETUP_FAIL:-} != "${0##*/}" ]]
SH

cat >"$mock_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo:%s\n' "$*" >>"$OMARCHY_TEST_SETUP_LOG"
[[ ${OMARCHY_TEST_SETUP_FAIL:-} != "sudo" ]]
SH

cat >"$mock_bin/xdg-settings" <<'SH'
#!/bin/bash
case $1 in
get) [[ -f $OMARCHY_TEST_BROWSER_FILE ]] && cat "$OMARCHY_TEST_BROWSER_FILE" ;;
set) printf '%s\n' "$3" >"$OMARCHY_TEST_BROWSER_FILE" ;;
esac
SH

cat >"$mock_bin/omarchy-test-installer" <<'SH'
#!/bin/bash
installer=${0##*/}

if [[ $installer == "omarchy-install-browser" && ${OMARCHY_TEST_REAL_BROWSER_INSTALL:-false} == "true" ]]; then
  exec "$ROOT/bin/omarchy-install-browser" "$@"
fi

case $installer in
omarchy-pkg-add)
  package=$1
  printf 'pkg:%s\n' "$package" >>"$OMARCHY_TEST_INSTALL_LOG"
  case $package in
  chromium) command=chromium ;;
  nano) command=nano ;;
  micro) command=micro ;;
  cursor-bin) command=cursor ;;
  sublime-text-4) command=sublime_text ;;
  vim) command=vim ;;
  neovim) command=nvim ;;
  esac
  ;;
omarchy-pkg-aur-add)
  package=$1
  printf 'aur:%s\n' "$package" >>"$OMARCHY_TEST_INSTALL_LOG"
  case $package in
  fresh-editor-bin) command=fresh ;;
  esac
  ;;
omarchy-install-browser)
  selection=$1
  printf 'browser:%s\n' "$selection" >>"$OMARCHY_TEST_INSTALL_LOG"
  case $selection in
  chromium) command=chromium ;;
  chrome) command=google-chrome-stable ;;
  brave) command=brave ;;
  brave-origin) command=brave-origin ;;
  edge) command=microsoft-edge-stable ;;
  firefox) command=firefox ;;
  zen) command=zen-browser ;;
  esac
  ;;
omarchy-install-terminal)
  command=$1
  printf 'terminal:%s\n' "$command" >>"$OMARCHY_TEST_INSTALL_LOG"
  ;;
omarchy-install-editor-*)
  editor=${installer#omarchy-install-editor-}
  printf 'editor:%s\n' "$editor" >>"$OMARCHY_TEST_INSTALL_LOG"
  case $editor in
  vscode) command=code ;;
  zed) command=zeditor ;;
  helix) command=helix ;;
  emacs) command=emacs ;;
  esac
  ;;
esac

[[ ${OMARCHY_TEST_INSTALL_FAIL:-false} != "true" ]] || exit 1
[[ ${OMARCHY_TEST_INSTALL_FALSE_SUCCESS:-false} != "true" ]] || exit 0
touch "$OMARCHY_TEST_INSTALLED_DIR/$command"
SH

for installer in \
  omarchy-pkg-add \
  omarchy-pkg-aur-add \
  omarchy-install-browser \
  omarchy-install-terminal \
  omarchy-install-editor-vscode \
  omarchy-install-editor-zed \
  omarchy-install-editor-helix \
  omarchy-install-editor-emacs; do
  ln -s omarchy-test-installer "$mock_bin/$installer"
done
for setup_command in \
  omarchy-install-chromium-copy-url \
  omarchy-install-chromium-ytdlp \
  omarchy-theme-set-browser; do
  ln -s omarchy-test-setup-call "$mock_bin/$setup_command"
done

chmod +x "$mock_bin"/*

export HOME="$test_home"
export PATH="$mock_bin:$ROOT/bin:$PATH"
export OMARCHY_PATH="$ROOT"
export OMARCHY_TEST_INSTALLED_DIR="$installed_dir"
export OMARCHY_TEST_INSTALL_LOG="$install_log"
export OMARCHY_TEST_TERMINAL_LOG="$terminal_log"
export OMARCHY_TEST_NOTIFICATION_LOG="$notification_log"
export OMARCHY_TEST_SETUP_LOG="$setup_log"
export OMARCHY_TEST_LAUNCHER_LOG="$launcher_log"
export OMARCHY_TEST_BROWSER_FILE="$browser_file"

assert_missing_opens_installer() {
  local type=$1
  local selection=$2

  : >"$terminal_log"
  "omarchy-default-$type" "$selection"
  mapfile -d '' -t terminal_args <"$terminal_log"
  [[ ${terminal_args[*]} == "omarchy-default-$type --install $selection" ]] ||
    fail "missing $selection opens its default installer in a terminal"
}

browser_cases=(
  'chromium chromium browser:chromium'
  'chrome google-chrome-stable browser:chrome'
  'brave brave browser:brave'
  'brave-origin brave-origin browser:brave-origin'
  'edge microsoft-edge-stable browser:edge'
  'firefox firefox browser:firefox'
  'zen zen-browser browser:zen'
)

terminal_cases=(
  'alacritty Alacritty.desktop'
  'foot foot.desktop'
  'ghostty com.mitchellh.ghostty.desktop'
  'kitty kitty.desktop'
)

editor_cases=(
  'code code editor:vscode'
  'cursor cursor pkg:cursor-bin'
  'zed zeditor editor:zed'
  'sublime_text sublime_text pkg:sublime-text-4'
  'helix helix editor:helix'
  'vim vim pkg:vim'
  'emacs emacs editor:emacs'
  'nvim nvim pkg:neovim'
  'nano nano pkg:nano'
  'micro micro pkg:micro'
  'fresh fresh aur:fresh-editor-bin'
)

for editor in nano micro fresh; do
  ln -s omarchy-test-editor "$mock_bin/$editor"
done

for entry in "${browser_cases[@]}"; do
  read -r selection command installer <<<"$entry"
  assert_missing_opens_installer browser "$selection"
done
for entry in "${terminal_cases[@]}"; do
  read -r selection desktop_id <<<"$entry"
  assert_missing_opens_installer terminal "$selection"
done
for entry in "${editor_cases[@]}"; do
  read -r selection command installer <<<"$entry"
  assert_missing_opens_installer editor "$selection"
done
pass "missing defaults open visible installers for every supported app"

if omarchy-default-editor unsupported >"$test_tmp/editor-usage" 2>&1; then
  fail "unsupported editor selection returns an error"
fi
grep -Fq 'Usage: omarchy-default-editor <code|cursor|zed|sublime_text|helix|vim|emacs|nvim|nano|micro|fresh>' \
  "$test_tmp/editor-usage" || fail "editor usage lists every supported selection"
pass "editor usage lists the supported selections"

for entry in "${browser_cases[@]}"; do
  read -r selection command installer <<<"$entry"
  rm -f "$installed_dir/$command"
  : >"$install_log"
  omarchy-default-browser --install "$selection"
  [[ $(<"$install_log") == "$installer" ]] || fail "$selection uses its browser installer"
  [[ $(omarchy-default-browser) == "$selection" ]] || fail "$selection becomes the default browser after installation"
done
pass "browser defaults install every missing browser before selection"

: >"$install_log"
: >"$setup_log"
rm -f "$installed_dir/chromium"
OMARCHY_TEST_REAL_BROWSER_INSTALL=true omarchy-default-browser --install chromium >/dev/null
[[ $(<"$install_log") == "pkg:chromium" ]] || fail "Chromium browser installer installs the package"
[[ $(omarchy-default-browser) == "chromium" ]] || fail "Chromium becomes the default after its full installer succeeds"
cmp -s "$ROOT/config/chromium-flags.conf" "$test_home/.config/chromium-flags.conf" ||
  fail "Chromium browser installer copies the default flags"
grep -Fxq 'sudo:mkdir -p /etc/chromium/policies/managed' "$setup_log" ||
  fail "Chromium browser installer creates its policy directory"
grep -Fxq 'sudo:chmod a+rw /etc/chromium/policies/managed' "$setup_log" ||
  fail "Chromium browser installer makes its policy directory writable"
grep -Fxq 'omarchy-install-chromium-copy-url:' "$setup_log" ||
  fail "Chromium browser installer registers the Copy URL host"
grep -Fxq 'omarchy-install-chromium-ytdlp:' "$setup_log" ||
  fail "Chromium browser installer registers the yt-dlp host"
grep -Fxq 'omarchy-theme-set-browser:' "$setup_log" ||
  fail "Chromium browser installer applies the current theme"
pass "Chromium browser installer restores the complete Omarchy setup"

omarchy-default-browser zen
rm -f "$installed_dir/chromium"
if OMARCHY_TEST_REAL_BROWSER_INSTALL=true OMARCHY_TEST_INSTALL_FAIL=true \
  omarchy-default-browser --install chromium >"$test_tmp/browser-package-failure" 2>&1; then
  fail "failed Chromium package installation returns an error"
fi
[[ $(omarchy-default-browser) == "zen" ]] || fail "failed Chromium package installation preserves the default browser"
[[ ! -e $installed_dir/chromium ]] || fail "failed Chromium package installation does not mark it installed"
pass "failed Chromium package installation preserves the current default"

if OMARCHY_TEST_REAL_BROWSER_INSTALL=true OMARCHY_TEST_SETUP_FAIL=sudo \
  omarchy-default-browser --install chromium >"$test_tmp/browser-install-failure" 2>&1; then
  fail "failed Chromium setup returns an error"
fi
[[ $(omarchy-default-browser) == "zen" ]] || fail "failed Chromium setup preserves the default browser"
grep -Fq 'Installing Chromium' "$test_tmp/browser-install-failure" ||
  fail "failed Chromium setup keeps progress visible in the terminal"
pass "failed Chromium setup preserves the current default"

for entry in "${terminal_cases[@]}"; do
  read -r selection desktop_id <<<"$entry"
  rm -f "$installed_dir/$selection"
  : >"$install_log"
  omarchy-default-terminal --install "$selection"
  [[ $(<"$install_log") == "terminal:$selection" ]] || fail "$selection uses the terminal installer"
  [[ $(tail -n 1 "$test_home/.config/xdg-terminals.list") == "$desktop_id" ]] ||
    fail "$selection becomes the default terminal after installation"
done
pass "terminal defaults install every missing terminal before selection"

for entry in "${editor_cases[@]}"; do
  read -r selection command installer <<<"$entry"
  rm -f "$installed_dir/$command"
  : >"$install_log"
  : >"$notification_log"
  omarchy-default-editor --install "$selection"
  [[ $(<"$install_log") == "$installer" ]] || fail "$selection uses its editor installer"
  [[ $(omarchy-default-editor) == "$command" ]] || fail "$selection becomes the default editor after installation"
  case $selection in
  code) name=VSCode ;;
  cursor) name=Cursor ;;
  zed) name=Zed ;;
  sublime_text) name="Sublime Text" ;;
  helix) name=Helix ;;
  vim) name=Vim ;;
  emacs) name=Emacs ;;
  nvim) name=Neovim ;;
  nano) name=Nano ;;
  micro) name=Micro ;;
  fresh) name=Fresh ;;
  esac
  case $selection in
  nano | micro | fresh)
    mapfile -d '' -t notification_args <"$notification_log"
    ((${#notification_args[@]} == 3)) || fail "$selection sends exactly three notification arguments"
    [[ ${notification_args[0]} == "-g" ]] || fail "$selection puts -g first in the notification arguments"
    [[ -n ${notification_args[1]} ]] || fail "$selection sends a nonempty notification glyph"
    [[ ${notification_args[2]} == "$name is now the default editor" ]] ||
      fail "$selection sends the exact success notification"
    ;;
  *)
    tr '\0' '\n' <"$notification_log" | grep -Fq "$name is now the default editor" ||
      fail "$selection sends a success notification after installation"
    ;;
  esac
done
pass "editor defaults install every missing editor before selection"

: >"$install_log"
: >"$terminal_log"
omarchy-default-browser zen
omarchy-default-terminal kitty
omarchy-default-editor nvim
[[ ! -s $install_log && ! -s $terminal_log ]] || fail "installed defaults skip installation"
pass "installed defaults are selected immediately"

previous_editor=$(omarchy-default-editor)
rm -f "$installed_dir/vim"
: >"$notification_log"
if OMARCHY_TEST_INSTALL_FAIL=true omarchy-default-editor --install vim >"$test_tmp/install-failure" 2>&1; then
  fail "failed default installation returns an error"
fi
[[ $(omarchy-default-editor) == "$previous_editor" ]] || fail "failed installation preserves the default"
[[ ! -s $notification_log ]] || fail "failed installation sends no success notification"
pass "failed installation preserves the current default"

for selection in nano micro fresh; do
  rm -f "$installed_dir/$selection"
  before_editor=$(omarchy-default-editor)
  : >"$notification_log"
  if OMARCHY_TEST_INSTALL_FALSE_SUCCESS=true omarchy-default-editor --install "$selection" >"$test_tmp/false-success-$selection" 2>&1; then
    fail "$selection false-success installation returns an error"
  fi
  [[ $(omarchy-default-editor) == "$before_editor" ]] || fail "$selection false-success preserves the default"
  [[ ! -e $installed_dir/$selection ]] || fail "$selection false-success does not mark the command installed"
  [[ ! -s $notification_log ]] || fail "$selection false-success sends no success notification"
done
pass "false-success installations preserve state and notifications"

isolated_home="$test_tmp/isolated-home"
mkdir -p "$isolated_home"
: >"$notification_log"
if HOME="$isolated_home" OMARCHY_TEST_INSTALL_FALSE_SUCCESS=true \
  omarchy-default-editor --install fresh >"$test_tmp/false-success-fresh-first-selection" 2>&1; then
  fail "Fresh false-success first selection returns an error"
fi
[[ ! -e $isolated_home/.local/state/omarchy/defaults/editor ]] ||
  fail "Fresh false-success first selection does not create state"
[[ ! -s $notification_log ]] || fail "Fresh false-success first selection sends no notification"
pass "false-success first selection leaves no state"

for editor in nano micro fresh; do
  touch "$installed_dir/$editor"
  printf '%s\n' "$editor" >"$test_home/.local/state/omarchy/defaults/editor"
  : >"$launcher_log"
  omarchy-launch-editor sample.txt
  grep -Fxq "tui:$editor sample.txt" "$launcher_log" || fail "$editor launches through the TUI wrapper"
  : >"$launcher_log"
  omarchy-launch-editor --inline sample.txt
  grep -Fxq "inline:$editor:sample.txt" "$launcher_log" || fail "$editor launches directly in inline mode"
done
pass "nano, micro, and fresh keep launcher command names consistent"
