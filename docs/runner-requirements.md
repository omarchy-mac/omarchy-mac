# Self-hosted runner for Install VM

The **Install VM** workflow (`.github/workflows/install-vm.yml`) runs only on a machine you register. It is `workflow_dispatch` plus a nightly schedule. It is not hooked to `pull_request`: this repo is public, and a desktop runner must not execute fork PRs.

## Labels

`./test/vm/setup-github-runner` registers with `--labels self-hosted,linux,ARM64,kvm`. GitHub also stamps OS/arch as `Linux` and `ARM64`. Matching is case-insensitive.

The job selects:

```
runs-on: [self-hosted, linux, ARM64]
```

The runner must show **Idle** with at least those three labels. Confirm at https://github.com/omarchy-mac/omarchy-mac/settings/actions/runners.

## Capabilities

- aarch64 Linux (Asahi / Omarchy). 16k host pages are expected.
- `systemd-nspawn` (from `systemd`)
- `gpg`, with outbound HKPS access to `keyserver.ubuntu.com` for rootfs signing-key retrieval
- passwordless `sudo` for the runner user (the setup script grants this to `github-runner`)
- outbound network (Arch Linux ARM tarball, pacman, AUR)
- several GB free on `/` — a full `install.sh` is a second Omarchy userspace. 34G disks fill up.

KVM is labeled but unused: a 4k Arch ARM QEMU guest cannot use KVM on a 16k host. The harness is nspawn sharing the host kernel.

## Register

From a terminal in this checkout:

```bash
./test/vm/setup-github-runner
```

Then Actions → **Install VM** → Run workflow. The optional target accepts a same-repository PR number, branch, tag, or full `refs/heads/*` / `refs/tags/*` ref. PRs whose head repository is a fork are rejected before repository code reaches the self-hosted runner, and other ref namespaces such as `refs/pull/*` are rejected. Nightly runs test the current default branch.

The harness keeps two host-side cache files under `~/.cache/omarchy-install-vm`: the downloaded Arch Linux ARM tarball and a prepared rootfs snapshot containing pacman keys, build tools, sudo, locale setup, and the disposable `ci` user. Every run extracts that snapshot into `/var/tmp/omarchy-install-vm/root`, so tests begin from the same clean base without repeating bootstrap work. Delete `prepared-aarch64-v*.tar.gz` to refresh it immediately; maintainers increment `PREPARED_CACHE_VERSION` in `test/vm/run-install` when bootstrap changes.

The manual workflow enables the idempotency pass by default, running `install.sh` twice in the same disposable machine. Disable it for a faster exploratory run. Nightly runs perform one install. Logs from installation, health checks, and the optional second pass are uploaded as the `install-vm-logs` artifact.

Run the same harness locally:

```bash
sudo ./test/vm/run-install
sudo OMARCHY_INSTALL_VM_IDEMPOTENCY=1 ./test/vm/run-install
```

## Staged AArch64 package builds

The **Build AArch64 Hyprland packages** workflow uses the same runner class to build `aquamarine`, `hyprtoolkit`, `hyprland-guiutils`, and `hyprland` in dependency order inside a disposable Arch Linux ARM userspace. Each result is installed in that userspace before the next package is built.

The job downloads the current `edge` `omarchy-aarch64.db.tar.zst` and `omarchy-aarch64.files.tar.zst`, updates copies with the new package archives, and records the exact Arch packaging commit used for every recipe. It then extracts a fresh copy of the verified rootfs and configures pacman to use the staged directory first with the live `edge` release as fallback for unchanged package files retained by the existing database. The consumer installs the full four-package stack and verifies dependency resolution and `aarch64` package metadata. Only after that clean consumer test passes does the job upload the complete staging directory as a seven-day Actions artifact. It does not publish or modify the GitHub release.

While account-level manual Actions dispatch is unavailable, the workflow has a temporary push trigger restricted to changes to its workflow or harness on `e2e-test-pipeline`; the job additionally requires repository `omarchy-mac/omarchy-mac` and actor `malik-na`. Remove that push trigger after the first staged build.

Both VM harnesses keep their rootfs caches under the invoking runner user's cache directory. The Arch Linux ARM rootfs and detached signature are downloaded over HTTPS, verified against the pinned official signing fingerprint `68B3537F39A313B3E574D06777193F152BDBE6A6`, and reverified before every cache use. Prepared rootfs snapshots are keyed by the verified archive digest and checksummed before extraction. Package-source fingerprints declared by each PKGBUILD are imported exactly and normal `makepkg` source-signature validation remains enabled.

GitHub Actions gives every build run and retry a separate work directory under `runner.temp`, preventing an interrupted build from contributing stale output to a later artifact. Both privileged workflows restrict manual dispatches to `malik-na`; the install workflow additionally retains its trusted scheduled run. Run the package builder locally on the ARM64 runner with:

```bash
sudo ./test/vm/build-aarch64-hyprland
```
