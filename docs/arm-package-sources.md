# ARM package sources

Apple Silicon installations use the regular Arch Linux ARM, Asahi Alarm, and Mac package repositories. The official `https://pkgs.omarchy.org/edge/$arch` repository has `Usage = Sync`, so it is refreshed but excluded from automatic package selection and upgrades.

The installer, system updater, and pacman channel refresh explicitly select `omarchy/hyprland`, `omarchy/hyprtoolkit`, and `omarchy/hyprland-guiutils` alongside a full system upgrade. Aquamarine and other dependencies resolve from the regular repositories. Dependency failures stop the transaction; no packages are ignored or dependencies bypassed.

The shared policy lives in `install/helpers/arm-package-sources.sh`. Package signatures are required and the existing Omarchy signing key is imported by its full fingerprint. Repository configuration preserves other repositories and mirror choices, saving `/etc/pacman.conf.bak` when it changes.

Use `omarchy update` for system upgrades. A bare `pacman -Syu` does not update the explicitly selected edge packages and can fail when their regular-repository dependencies change ABI. Edge is rolling; versions are resolved together at transaction time rather than pinned.
