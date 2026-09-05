# Apple M3 generation

State of Omarchy Mac on M3, M3 Pro and M3 Max Macs, what the repo does about it, and what changes the day Asahi ships the rest. Written against the public Asahi trees as of September 2026; the first section is the part that goes stale.

## Where Asahi is

Asahi's kernel (`asahi` branch, tagged releases from 7.1.6 on, which is what Asahi Alarm ships) carries device trees for every M3 machine, including the 14 and 16-inch MacBook Pros (`t6030-j514s`, `t6030-j516s`), the M3 Max variants (`t6031`, `t6034`) and the plain M3 machines (`t8122`). m1n1 1.6.1 boots them. U-Boot knows the SoC. The Asahi installer lists every M3 device, gated to expert mode, against the macOS 14.8.3 firmware.

What boots on that kernel: CPU frequency scaling, NVMe, PCIe, Wi-Fi, Bluetooth, keyboard, trackpad, speakers and microphones, USB and Thunderbolt, battery, suspend. Asahi's own table: https://asahilinux.org/docs/platform/feature-support/m3/

What does not exist in any public tree:

- **The display driver for M3.** The M3 needs the DCP firmware ABI from macOS 14.7/14.8.3. A first cut of that ABI is public (`iomfb_v14_7` in `asahi-wip-7.2` and in James Calligeros' `dcp/14.8.3` branch), but no branch wires it to the M3 device trees. The Asahi progress report for Linux 7.2 says the M3 DCP work is "almost at feature parity"; it is on the developers' machines. Without it the kernel draws on the framebuffer the boot firmware leaves behind (simpledrm): the internal panel works at native resolution, there is no brightness control, no external display, and sleep may not bring the panel back.
- **The GPU driver for M3 (G15).** The Asahi DRM driver knows G13 (M1) and G14 (M2); its hardware table has no M3 entry in `asahi`, `asahi-wip`, any `gpu/*` branch, or any core developer's fork. Mesa has no G15 either. Asahi lists the M3 GPU as "TBA". Everything renders through llvmpipe.

Asahi said on 2026-08-26 it is "almost ready to cut an official release" for M3. That release will bring the display driver. The GPU is a separate, later piece of work.

## What the repo does on an M3

- `bin/omarchy-hw-apple-soc` identifies the generation from the device tree (`m1`, `m2`, `m3`, `m4`), prints the machine codename, and answers `--gpu`: whether the Asahi GPU driver has actually bound. Everything else keys off that rather than off a list of models, so it is right on the day the driver lands and needs no migration.
- `install/hardware/vulkan.sh` installs `vulkan-asahi` only when the GPU driver is bound. Installing it without the driver is harmless but makes `omarchy-hw-vulkan` claim Vulkan works.
- `install/hardware/apple/m3.sh` says on the console what the machine will and will not do, and records the SoC in `/etc/omarchy/apple-soc`.
- `default/hypr/apple.lua`, loaded from `envs.lua` next to the NVIDIA one, turns on software-rendering settings when the SoC command says there is no GPU driver: `AQ_NO_MODIFIERS`, software cursors, no direct scanout, variable frame rate. Checked at every session start, so a kernel that binds the driver turns them off by itself.
- `bin/omarchy-mac-setup` warns before "Start?" on an M3.
- `bin/omarchy-mac-asahi-install` runs on macOS and is the actual unlock: see below.
- `pkgbuilds/linux-asahi-wip` and `bin/omarchy-mac-kernel-wip` build any Asahi branch as a second kernel: see below.

## Installing on an M3

The Asahi Alarm bootstrap refuses an M3 out of the box, for two reasons stacked on top of each other:

1. **The installer package.** Asahi's own installer (asahi-installer 0.9.0 and later) has every M3 device in its table, gated to expert mode, against the 14.8.3 firmware. Asahi Alarm ships its own build of that installer, and as of 0.8.4 it is an older one whose table ends at M2: on an M3 it prints "This device is not supported yet!" and exits, before the expert-mode question, which the installer only asks when `EXPERT` is set in the environment anyway. The installer is data-driven, so Asahi's package runs unchanged against Asahi Alarm's image list and images.
2. **`installer_data.json`.** Each Asahi Alarm image lists the macOS firmware versions it was built against, and none lists 14.8.3, so even an M3-aware installer finds no firmware the image accepts and stops with "Your system firmware is too old" (asahi-installer issue 438). The Asahi developers' instruction for M3 testing is to add "14.8.3" to that list by hand (asahi-installer PR 424).

`bin/omarchy-mac-asahi-install` undoes both. From macOS:

```bash
curl -fsSL https://raw.githubusercontent.com/omarchy-mac/omarchy-mac/quattro/bin/omarchy-mac-asahi-install | bash
```

It fetches Asahi Alarm's installer package and image list from asahi-alarm.org as the official bootstrap does, adds "14.8.3" to every image's `supported_fw`, and checks the package's device table for M3. When the table ends at M2 it fetches Asahi's own installer from cdn.asahilinux.org instead and points it at the Asahi Alarm images; the day Asahi Alarm rebuilds its installer with the M3 table, the wrapper uses that one with no change. It then sets `EXPERT=1`, prints a briefing, and hands over. Answer **yes** to expert mode (the installer refuses an M3 without it), pick **Asahi Alarm Minimal (BTRFS)**, and size the partition. On an M1 or M2 it runs the stock package and data unchanged; `--data-only` writes the patched JSON to `/tmp/asahi-install/` without running anything.

Then boot Arch and run `omarchy-mac-setup` as on any other Mac.

The images are built from the released kernel, so the installed system is the one described above: no display driver, software rendering. The image built on 2026-08-31 carries linux-asahi 7.1.6 and m1n1 1.6.1, both of which have the M3 device trees; `update-m1n1` concatenates every `t6*` and `t81*` device tree into the boot image, so the right one reaches m1n1.

Sizing: the installer keeps 38 GB free inside the macOS container for updates, and macOS cannot shrink below what it uses. Delete from macOS first if Linux needs more.

## Trying a newer kernel

When Asahi pushes M3 display support it will be on a branch before it is in a tagged release, and Asahi Alarm follows tagged releases. `bin/omarchy-mac-kernel-wip` builds `pkgbuilds/linux-asahi-wip` from any branch of any fork with Asahi Alarm's own kernel config and installs it **next to** `linux-asahi`, not over it: GRUB lists both kernels, so a branch that does not boot costs one reboot.

```bash
omarchy-mac-kernel-wip                                  # AsahiLinux/linux, branch asahi-wip
omarchy-mac-kernel-wip --repo chadmed/linux --branch dcp/14.8.3
omarchy-mac-kernel-wip --remove
```

About an hour on an M3 Pro, plugged in. The package installs the branch's device trees into its module directory, and Asahi Alarm's `update-m1n1` takes the device trees from the newest module directory, so a branch that adds the M3 display nodes reaches m1n1 through the same install. After a reboot, `omarchy-hw-apple-soc --gpu` and `ls /sys/class/drm` say what bound.

The default branch is `asahi-wip`, Asahi's integration branch. The day the M3 DCP branch is public, that default is the one line to change.

## Known unknowns

- Whether `AQ_NO_MODIFIERS` and software cursors are enough for Hyprland on simpledrm at 3456x2234 has not been measured on an M3; the settings are the ones that work in VMs on simpledrm. Halving the monitor scale in `hypr/monitors.lua` is the first thing to try if it is slow.
- `enable-notch.sh` sets `appledrm show_notch=1`; with no display driver the module never binds and the option is inert.
- Keyboard backlight and the 3.5 mm jack are in Asahi's 7.3 kernel; Asahi Alarm is on 7.1.
