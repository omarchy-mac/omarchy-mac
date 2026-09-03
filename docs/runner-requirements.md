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

Then Actions → **Install VM** → Run workflow. Locally: `sudo ./test/vm/run-install`.
