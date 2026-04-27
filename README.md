# jetson-restore

Restore stock NVIDIA L4T Ubuntu onto Jetson Orin dev kits from any modern Linux host. One command, scriptable, idempotent.

## Why

NVIDIA's official flashing toolchain assumes an Ubuntu 20.04/22.04 host. From Arch (or NixOS, Fedora, …) the existing options are: run NVIDIA's SDK Manager Docker image (interactive, ~2 GB, devzone login), follow community gists (unpackaged, untested), or patch NVIDIA's scripts for native Arch (ongoing maintenance burden). `jetson-restore` packages the working approach — a thin host wrapper plus a pinned Ubuntu container — as a maintained tool with tests, idempotent host setup, and reproducible builds.

See [`docs/superpowers/specs/2026-04-27-jetson-restore-design.md`](docs/superpowers/specs/2026-04-27-jetson-restore-design.md) for the design and prior-art survey.

## Supported targets (v1)

- Orin Nano dev kit (NVMe)
- AGX Orin dev kit (NVMe)
- JetPack 6.2.1 / L4T R36.4.4

## Quick start

1. Install dependencies:

   - Arch: `sudo pacman -S podman nfs-utils sudo`
   - Ubuntu: `sudo apt install podman nfs-kernel-server sudo`

2. Plug the dev kit into this host via USB-C and put it in recovery mode (see [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) if you're not sure how).

3. Run:

   ```bash
   git clone https://github.com/<owner>/jetson-restore
   cd jetson-restore
   ./bin/jetson-restore --target orin-nano-devkit
   ```

4. Wait. The first run downloads ~8 GB of BSP and rootfs into `./work/cache/`. Subsequent runs are fast.

5. When the script reports "flash complete", reboot the device. It boots into stock L4T Ubuntu 22.04.

## Other commands

- `jetson-restore --check` — preflight only, no flash.
- `jetson-restore --dry-run` — print every command that would run.
- `jetson-restore --no-sudo` — write sudo commands to `./work/preflight.sh` for manual execution.
- `jetson-restore uninstall` — remove the udev rule, NM keyfile, NFS export, and stop nfs-server iff jetson-restore started it.

## What it changes on your host

Persistent (idempotent) — left in place across runs:

- `/etc/udev/rules.d/70-jetson-restore.rules` — non-root access to VID `0955` and USB autosuspend disable.
- `/etc/NetworkManager/system-connections/jetson-restore-rndis.nmconnection` — ignore the recovery RNDIS interface.
- `/etc/exports.d/jetson-restore.conf` — NFS export of `./work/Linux_for_Tegra` to `192.168.55.0/24` only.
- `nfs-server` started and enabled (idle daemon listening on port 2049).

Run `jetson-restore uninstall` to remove all of the above.

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — two-layer design summary for contributors.
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — recovery mode, subnet conflicts, USB autosuspend, NFS startup.
- [`docs/superpowers/specs/2026-04-27-jetson-restore-design.md`](docs/superpowers/specs/2026-04-27-jetson-restore-design.md) — full design spec.
- [`CHANGELOG.md`](CHANGELOG.md) — release notes and pre-tag readiness checklist.

## Status

**v1 in progress.** The unit test suite (65 bats tests) runs in CI on every push. Two tests fail by design until a maintainer fills in the real SHA-256 values for the JetPack 6.2.1 BSP and rootfs tarballs in [`jetpacks/6.2.1.conf`](jetpacks/6.2.1.conf) — that's the forcing function. Hardware end-to-end on real Orin Nano + AGX Orin dev kits is gated on `JETSON_RESTORE_E2E=1` and run before each release.

## License

Apache-2.0.
