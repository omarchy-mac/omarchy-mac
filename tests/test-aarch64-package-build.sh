#!/bin/bash
# Static safety and dependency-order checks for the self-hosted package build.

set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS="$ROOT/test/vm/build-aarch64-hyprland"
WORKFLOW="$ROOT/.github/workflows/build-aarch64-packages.yml"
INSTALL_WORKFLOW="$ROOT/.github/workflows/install-vm.yml"
INSTALL_HARNESS="$ROOT/test/vm/run-install"
pass=0
failures=0

check() {
  local label="$1"
  shift
  if "$@"; then
    echo "✓ $label"
    ((++pass))
  else
    echo "✗ $label"
    ((++failures))
  fi
}

not() {
  ! "$@"
}

install_rootfs_is_verified() {
  grep -q 'TARBALL_URL=.*https://os.archlinuxarm.org/' "$INSTALL_HARNESS" &&
    grep -q '^ROOTFS_SIGNING_FINGERPRINT=68B3537F39A313B3E574D06777193F152BDBE6A6$' "$INSTALL_HARNESS" &&
    grep -q 'verify_rootfs "\$tarball" "\$signature"' "$INSTALL_HARNESS"
}

prepared_caches_are_checked() {
  grep -q 'rootfs_digest=.*sha256sum' "$HARNESS" &&
    grep -q 'sha256sum -c' "$HARNESS" &&
    grep -q 'rootfs_digest=.*sha256sum' "$INSTALL_HARNESS" &&
    grep -q 'sha256sum -c' "$INSTALL_HARNESS"
}

recipe_keys_are_imported() {
  grep -q 'makepkg --printsrcinfo' "$HARNESS" &&
    grep -q 'validpgpkeys' "$HARNESS" &&
    grep -q 'grep -qx "\$normalized"' "$HARNESS"
}

consumer_uses_staged_repo() {
  local local_line remote_line
  local_line=$(grep -n "printf 'Server = file:///staging" "$HARNESS" | cut -d: -f1)
  remote_line=$(grep -n "printf 'Server = %s" "$HARNESS" | cut -d: -f1)

  [[ -n $local_line && -n $remote_line ]] &&
    (( local_line < remote_line )) &&
    grep -q -- '--setenv=OMARCHY_AARCH64_REPO_URL="\$REPO_URL"' "$HARNESS" &&
  grep -q 'pacman -S --noconfirm "\${packages\[@\]}"' "$HARNESS"
}

expected=$'aquamarine\nhyprtoolkit\nhyprland-guiutils\nhyprland'
check "packages are built in dependency order" \
  test "$("$HARNESS" --print-plan)" = "$expected"
check "harness parses as bash" bash -n "$HARNESS"
check "workflow has a manual trigger" grep -q '^  workflow_dispatch:' "$WORKFLOW"
check "temporary push trigger names only the pipeline branch" \
  grep -q '^      - e2e-test-pipeline$' "$WORKFLOW"
check "temporary push execution is fenced to the maintainer" \
  grep -q "github.actor == 'malik-na'" "$WORKFLOW"
check "manual package builds are fenced to the maintainer" \
  grep -q "workflow_dispatch' && github.actor == 'malik-na'" "$WORKFLOW"
check "manual install targets are fenced to the maintainer" \
  grep -q "workflow_dispatch' && github.actor == 'malik-na'" "$INSTALL_WORKFLOW"
check "scheduled install remains allowed" \
  grep -q "github.event_name == 'schedule'" "$INSTALL_WORKFLOW"
check "self-hosted job has read-only contents permission" \
  grep -q '^  contents: read$' "$WORKFLOW"
check "workflow does not publish release assets" \
  not grep -Eq 'release upload|gh[[:space:]]+release|contents:[[:space:]]+write' "$WORKFLOW" "$HARNESS"
check "each package is installed for downstream builds" \
  grep -q 'pacman -U --needed --noconfirm' "$HARNESS"
check "staging starts from both live repository indexes" \
  grep -q '"\$REPO_NAME.db.tar.zst" "\$REPO_NAME.files.tar.zst"' "$HARNESS"
check "rootfs download uses HTTPS" \
  grep -q 'TARBALL_URL=.*https://os.archlinuxarm.org/' "$HARNESS"
check "rootfs signer is pinned to the official fingerprint" \
  grep -q '^ROOTFS_SIGNING_FINGERPRINT=68B3537F39A313B3E574D06777193F152BDBE6A6$' "$HARNESS"
check "rootfs signature is fetched and verified" \
  grep -q '"\$TARBALL_URL.sig"' "$HARNESS"
check "cached rootfs is reverified" \
  grep -q 'verify_rootfs "\$tarball" "\$signature"' "$HARNESS"
check "workflow uses a run-scoped work directory" \
  grep -q 'runner.temp.*github.run_id.*github.run_attempt' "$WORKFLOW"
check "rerun artifacts are attempt-scoped" \
  test "$(grep -c 'name: aarch64-.*github.run_id.*github.run_attempt' "$WORKFLOW")" = "2"
check "staged repository is uploaded only after success" \
  not grep -q 'if: always()' < <(sed -n '/name: Upload staged repository/,/name: Upload build log/p' "$WORKFLOW")
check "build logs are uploaded even after failure" \
  grep -q 'if: always()' < <(sed -n '/name: Upload build log/,$p' "$WORKFLOW")
check "install rootfs also uses signed HTTPS verification" install_rootfs_is_verified
check "prepared caches are tied to rootfs digest and checksummed" prepared_caches_are_checked
check "package source signature checks are not bypassed" \
  not grep -q -- '--skippgpcheck' "$HARNESS"
check "PKGBUILD signing fingerprints are imported exactly" recipe_keys_are_imported
check "recipe commit SHAs are recorded" \
  grep -q 'source-commits.txt' "$HARNESS"
check "consumer starts from the verified rootfs, not builder state" \
  grep -q 'tar -xzf "\$tarball" -C "\$WORK/consumer-root"' "$HARNESS"
check "consumer uses staged files before the live repository fallback" consumer_uses_staged_repo
check "consumer verifies aarch64 package metadata" \
  grep -q '\[\[ \$architecture == "aarch64" \]\]' "$HARNESS"

echo
echo "=== $pass checks passed, $failures failed ==="
(( failures == 0 ))
