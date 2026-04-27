# jetson-restore

Restore stock NVIDIA L4T Ubuntu onto Jetson Orin dev kits from any modern Linux
host. One command, scriptable, idempotent.

## Why

NVIDIA's official flashing toolchain assumes an Ubuntu 20.04/22.04 host. From
Arch (or NixOS, Fedora, …) the existing options are: run NVIDIA's SDK Manager
Docker image (interactive, ~2 GB, devzone login), follow community gists
(unpackaged, untested), or patch NVIDIA's scripts for native Arch (ongoing
maintenance burden). `jetson-restore` packages the working approach — a thin
host wrapper plus a pinned Ubuntu container — as a maintained tool with tests,
idempotent host setup, and reproducible builds.

See
[`docs/superpowers/specs/2026-04-27-jetson-restore-design.md`](docs/superpowers/specs/2026-04-27-jetson-restore-design.md)
for the design and prior-art survey.

## Supported targets (v1)

- Orin Nano dev kit (NVMe)
- AGX Orin dev kit (NVMe)
- JetPack 6.2.1 / L4T R36.4.4

## Quick start

1. Install dependencies:
   - Arch: `sudo pacman -S podman nfs-utils sudo`
   - Ubuntu: `sudo apt install podman nfs-kernel-server sudo`

2. Put the dev kit in recovery mode (see [Recovery mode](#recovery-mode) below).

3. Run:

   ```bash
   git clone https://github.com/<owner>/jetson-restore
   cd jetson-restore
   ./bin/jetson-restore --target orin-nano-devkit
   ```

4. Wait. The first run downloads ~8 GB of BSP and rootfs into `./work/cache/`.
   Subsequent runs are fast.

5. When the script reports "flash complete", reboot the device. It boots into
   stock L4T Ubuntu 22.04.

## Other commands

- `jetson-restore --check` — preflight only, no flash.
- `jetson-restore --dry-run` — print every command that would run.
- `jetson-restore --no-sudo` — write sudo commands to `./work/preflight.sh` for
  manual execution.
- `jetson-restore uninstall` — remove the udev rule, NM keyfile, NFS export, and
  stop nfs-server iff jetson-restore started it.

## What it changes on your host

Persistent (idempotent) — left in place across runs:

- `/etc/udev/rules.d/70-jetson-restore.rules` — non-root access to VID `0955`
  and USB autosuspend disable.
- `/etc/NetworkManager/system-connections/jetson-restore-rndis.nmconnection` —
  ignore the recovery RNDIS interface.
- `/etc/exports.d/jetson-restore.conf` — NFS export of `./work/Linux_for_Tegra`
  to `192.168.55.0/24` only.
- `nfs-server` started and enabled (idle daemon listening on port 2049).

Run `jetson-restore uninstall` to remove all of the above.

## Recovery mode

Before running `jetson-restore`, the dev kit must be in forced recovery mode
and visible on this host's USB bus as `0955:7e19` (Orin Nano) or `0955:7023`
(AGX Orin). Verify at any time with `lsusb | grep 0955`.

### Orin Nano dev kit

**USB port:** the USB-C port on the carrier board (front edge, alongside the
M.2 NVMe slot). Connect this to a USB port on the host — direct, not through
a hub.

**Procedure (jumper-based forced recovery):**

1. Disconnect the barrel-jack power so the dev kit is fully off.
2. Place a jumper across pins **9 and 10** of the **J14 button header**
   (these are the FC REC and GND pins). Pin 1 is at the corner closest to the
   carrier-board edge.
3. Connect a USB-C **data** cable from the carrier board's USB-C port to this
   host.
4. Reapply power.
5. Verify: `lsusb | grep '0955:7e19'` should show `NVIDIA Corp. APX`.

The jumper can stay in place during flashing — remove it only when you want
the device to boot normally afterward.

### AGX Orin dev kit

**USB port:** the **front USB-C port** on the dev kit (the one closest to the
power button is the standard flashing port; if `lsusb` doesn't see the device,
try the other front USB-C port).

**Procedure (button-combo forced recovery):**

1. Connect a USB-C **data** cable from the dev kit's front USB-C port to this
   host.
2. Power the dev kit off, or press **RESET** and wait for the fans to stop.
3. Press and **hold** the **FORCE RECOVERY** button (on the side, between
   POWER and RESET).
4. While still holding FORCE RECOVERY, press and release the **POWER** button.
5. Release FORCE RECOVERY after ~2 seconds.
6. Verify: `lsusb | grep '0955:7023'` should show `NVIDIA Corp. APX`.

### Cable matters

Use a known-good USB-C **data** cable. Charge-only USB-C cables silently fail:
the device will not appear on the USB bus at all and `jetson-restore` will
time out at the recovery-mode preflight check with no other clue. If a cable
that worked yesterday stops working today, suspect the cable before suspecting
the board.

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — two-layer design summary for
  contributors.
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — recovery mode, subnet
  conflicts, USB autosuspend, NFS startup.
- [`docs/superpowers/specs/2026-04-27-jetson-restore-design.md`](docs/superpowers/specs/2026-04-27-jetson-restore-design.md)
  — full design spec.
- [`CHANGELOG.md`](CHANGELOG.md) — release notes and pre-tag readiness
  checklist.

## Status

**v1 in progress.** The unit test suite (65 bats tests) runs in CI on every
push. Two tests fail by design until a maintainer fills in the real SHA-256
values for the JetPack 6.2.1 BSP and rootfs tarballs in
[`jetpacks/6.2.1.conf`](jetpacks/6.2.1.conf) — that's the forcing function.
Hardware end-to-end on real Orin Nano + AGX Orin dev kits is gated on
`JETSON_RESTORE_E2E=1` and run before each release.

## License

Apache-2.0.
