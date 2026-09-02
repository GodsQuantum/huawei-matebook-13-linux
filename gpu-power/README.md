# GPU & Power — on-demand NVIDIA MX250

> **Français : [README.FR.md](README.FR.md)**

This section solves a specific Linux problem on Huawei MateBook 13 models equipped with an Intel iGPU and NVIDIA GeForce MX250: **how to keep the dGPU truly out of the way while idle, yet launch selected applications on NVIDIA without logging out or rebooting.**

## Why not leave Hybrid enabled?

On the validated MateBook 13/MX250 setup, a permanently available NVIDIA dGPU costs measurable battery life even when it appears idle. The target idle state is therefore stricter than ordinary PRIME Hybrid mode:

```text
Intel iGPU: present and driving the desktop
MX250:      removed from PCI
NVIDIA:     modules unloaded
PCIe port:  runtime-suspended when possible
```

When a managed program starts, the GPU is hot-added, NVIDIA R580 is loaded, the program receives PRIME Render Offload variables, and the desktop compositor stays on Intel. When the last managed workload exits, the NVIDIA modules are unloaded and the GPU is removed from PCI again.

## Validated configuration

Validated end-to-end on:

- Huawei MateBook 13 generation using Intel graphics + NVIDIA GeForce MX250;
- MX250 PCI ID `10de:1d13` / GP108M (Pascal);
- KDE Plasma Wayland;
- NVIDIA proprietary R580 branch.

The script detects the actual Intel GPU BDF, MX250 BDF and PCIe root port dynamically. It refuses non-Huawei hardware by default and always requires the MX250 PCI ID.

### Driver requirement: R580

NVIDIA 590 and newer dropped Pascal support. MX250 owners must remain on the proprietary R580 legacy branch.

The installer has package-manager paths for:

- **Arch / CachyOS** — `nvidia-580xx-dkms` + `nvidia-580xx-utils` (repository or AUR helper depending on the distribution);
- **Fedora** — RPM Fusion `akmod-nvidia-580xx` / `xorg-x11-drv-nvidia-580xx` packages when the repository is already enabled;
- **Debian / Ubuntu** — `nvidia-driver-580` when provided by enabled repositories.

The script intentionally does **not** silently enable third-party repositories.

### Do not stack GPU mode switchers

This manager owns the MX250 PCI/module lifecycle while it is installed. Do not perform concurrent mode changes with `optimus-manager`, EnvyControl, a supergfxctl panel toggle, or another tool that also loads/unloads/removes the NVIDIA GPU. If supergfxctl is already present, leave it in **Integrated** and do not switch modes while an on-demand workload is active.

## Architecture

### Idle / boot

The installer creates:

- a modprobe policy preventing NVIDIA and nouveau from auto-loading;
- a small root power helper;
- a boot service that unloads NVIDIA and removes the MX250 from PCI before the graphical login whenever possible;
- a stable Intel DRM alias;
- a KWin systemd-user drop-in on Plasma so KWin remains on Intel;
- a periodic cleanup timer for crashed/daemonized workloads.

### Launching a managed application

`huawei-matebook-dgpu-run` requests a lease from the root helper. The first lease:

1. performs a PCI rescan;
2. locates `10de:1d13` dynamically;
3. loads `nvidia`, `nvidia_modeset`, `nvidia_drm` and `nvidia_uvm`;
4. verifies that no desktop/compositor process grabbed NVIDIA unexpectedly;
5. launches the application with NVIDIA PRIME Render Offload variables.

Additional managed applications get additional leases and can share the dGPU concurrently.

### Closing applications

When a runner exits, its lease is removed. The GPU is powered down only when:

- no valid managed lease remains; and
- no process still has NVIDIA device/render nodes open.

Then the helper unloads the NVIDIA modules and removes the MX250 PCI function. A periodic user timer retries cleanup after crashes or programs that briefly outlive their launcher.

## Install

Run as your **normal user**, not root:

```bash
chmod +x huawei-matebook-13-gpu-manager.sh
./huawei-matebook-13-gpu-manager.sh install
```

French UI:

```bash
./huawei-matebook-13-gpu-manager.sh --lang fr install
```

A reboot is expected after the initial installation so the boot policy and KWin environment are applied cleanly.

### Upgrade / repair behavior

Re-running `install` is idempotent and also performs upgrades. Version 3 can import supported v1/v2 state from existing launchers, backups, Steam Launch Options and adjacent portable manifests. Migration uses a snapshot/rollback boundary; legacy helpers are removed only after the new infrastructure passes its GPU smoke test and returns to full Integrated idle.

On CachyOS/Arch systems actively using Limine, the manager calls `limine-mkinitcpio` directly so initramfs images and Limine entries are rebuilt together. Other systems fall back to their appropriate `mkinitcpio`, `dracut` or `update-initramfs` path.

## Add or remove applications

Interactive:

```bash
./huawei-matebook-13-gpu-manager.sh
```

CLI:

```bash
./huawei-matebook-13-gpu-manager.sh add
./huawei-matebook-13-gpu-manager.sh add DaVinciResolve.desktop
./huawei-matebook-13-gpu-manager.sh remove DaVinciResolve.desktop
./huawei-matebook-13-gpu-manager.sh list
```

The manager creates a user-local `.desktop` override and preserves the original local launcher when one already exists. It sets `DBusActivatable=false` for managed launchers so the desktop actually follows the modified `Exec=` line.

Since v3, canonical per-user state is versioned under the XDG configuration directory (`~/.config/huawei-matebook-gpu-manager/state.json` by default), while the script keeps a portable embedded manifest for reinstall recovery. `install` is also the upgrade/repair command: it can detect and import supported older manager generations, reconcile the current installation transactionally, validate the MX250 cycle, and only then remove obsolete legacy infrastructure. A newer on-disk install schema is never overwritten by an older manager.

## One-off command

```bash
./huawei-matebook-13-gpu-manager.sh run -- glxinfo -B
./huawei-matebook-13-gpu-manager.sh run -- blender
```

## Steam

The Steam client itself should stay on Intel. Individual games can be wrapped with the on-demand runner.

```bash
./huawei-matebook-13-gpu-manager.sh steam-add 730
./huawei-matebook-13-gpu-manager.sh steam-remove 730
```

Steam must be completely closed while its `localconfig.vdf` is edited. A timestamped backup is created before every edit. Existing Launch Options are preserved and restored when a game is removed from management.

Direct `localconfig.vdf` editing is inherently less stable than the freedesktop `.desktop` path, so Steam support is marked **experimental** and intentionally conservative.

## Status and test

```bash
./huawei-matebook-13-gpu-manager.sh status
./huawei-matebook-13-gpu-manager.sh doctor
./huawei-matebook-13-gpu-manager.sh test
```

A healthy idle result should show the MX250 as absent. The test should briefly report an NVIDIA renderer, then return to an absent dGPU with no NVIDIA modules/users.

## Plasma / KWin detail

On modern Plasma Wayland, KWin may automatically open newly appearing DRM/render nodes. If it opens the MX250, the NVIDIA modules cannot be unloaded and the dGPU remains awake.

The manager installs a per-user systemd drop-in with:

```text
KWIN_DRM_DEVICES=/dev/dri/huawei-matebook-intel
KWIN_RENDER_NODES=
```

The second setting is particularly relevant to Plasma 6.7+ GPU-manager behavior. The root helper also verifies the outcome at runtime and **fails closed** if a compositor grabs NVIDIA before the managed application starts.

## Other desktops

The PCI/NVIDIA/PRIME core is not inherently KDE-specific, but compositor behavior is. Plasma Wayland is the validated path. On another compositor, the helper will refuse to continue if it detects an unexpected process holding NVIDIA immediately after hot-add.

Please report successful or failed tests with generic system information so support can be expanded without weakening this safeguard.

## Uninstall

```bash
./huawei-matebook-13-gpu-manager.sh uninstall
```

This restores managed desktop launchers, removes the helper/services/KWin override and leaves NVIDIA packages installed. Reboot afterward.

## Safety / recovery

The manager does not flash firmware, write GPU ROMs or modify ACPI tables. Its privileged operations are limited to module loading/unloading, PCI rescan/remove, udev/systemd configuration and a narrowly scoped sudoers rule.

If the graphical session ever grabs NVIDIA unexpectedly, the helper refuses the app launch instead of force-unloading a live GPU. Rebooting returns to the boot-time Integrated policy.

## Contributing test results

Useful reports include:

- exact MateBook 13 revision if known **without serial number**;
- distro and kernel;
- desktop environment and Wayland/X11;
- `lspci -nn` lines for Intel display + NVIDIA MX250;
- script `status` output;
- whether idle returns to MX250 absent after the last workload exits.

Do not attach DMI serials, UUIDs, home-directory paths or unrelated system dumps.
