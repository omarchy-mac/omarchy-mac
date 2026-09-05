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
