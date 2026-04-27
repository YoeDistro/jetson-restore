# jetson-restore

Restore stock NVIDIA L4T Ubuntu onto Jetson Orin dev kits from any modern Linux host. One command, scriptable, idempotent.

## Supported targets (v1)

- Orin Nano dev kit (NVMe)
- AGX Orin dev kit (NVMe)
- JetPack 6.2.1 / L4T R36.4.4

## Quick start

1. Install dependencies:

   - Arch: `sudo pacman -S podman nfs-utils sudo`
   - Ubuntu: `sudo apt install podman nfs-kernel-server sudo`

2. Plug the dev kit into this host via USB-C and put it in recovery mode (see TROUBLESHOOTING.md if you're not sure how).

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

## License

Apache-2.0.
