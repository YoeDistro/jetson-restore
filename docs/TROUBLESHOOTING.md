# Troubleshooting

## "device not in recovery mode"

The recovery-mode procedure (per board) and USB port locations live in the
top-level README's [Recovery mode](../README.md#recovery-mode) section.

Quick check: `lsusb | grep 0955`. Two common causes when the board *should* be
in recovery mode but isn't visible:

- **Charge-only USB-C cable.** Swap to a known-good data cable.
- **USB hub between host and dev kit.** Plug directly into the host.

## "another route exists for 192.168.55.0/24"

Something on your host is already using the RNDIS subnet — typically a VPN,
VirtualBox, or a Docker bridge. Either bring it down for the duration of the
flash, or change its subnet.

## Flash hangs at "Sending bootloader"

USB autosuspend is the usual cause. The udev rule disables it for VID 0955, but
if you're on a host where udev rules don't apply (some immutable distros),
disable it globally for the flash:

    echo -1 | sudo tee /sys/module/usbcore/parameters/autosuspend

## "host nfs-server is running"

NVIDIA's flash container manages NFS itself via `--net host`, which binds
the host kernel's `nfsd` port. A host-side `nfs-server` would collide on
port 2049 and the container's restart would clobber the host's exports.
Stop it first:

    sudo systemctl stop nfs-server      # Arch / RHEL
    sudo systemctl stop nfs-kernel-server  # Ubuntu / Debian

Re-run jetson-restore. If you don't want `nfs-server` to come back at boot,
also `sudo systemctl disable nfs-server`. We don't need NFS on the host
for this tool to work.

## "Why is the AGX Orin flash writing to both `/dev/mmcblk0` and `/dev/nvme0n1p1`?"

That's expected. The AGX Orin Devkit's BootROM only reads QSPI flash and
eMMC — it can't read NVMe directly — so the boot chain has to live on
internal storage even when you target NVMe. With `--storage nvme` you'll
see:

- **eMMC** gets bootloader, kernel, dtb, ESP, recovery, *and* a populated
  fallback `APP` partition.
- **NVMe** (`/dev/nvme0n1p1`) gets the primary `APP` (rootfs) the system
  actually boots into.

The eMMC fallback rootfs means the system still comes up if NVMe is
missing or corrupt. The line `Successfully flashed the eMMC.` appearing
mid-run is normal — the script then proceeds to the NVMe half.

For an eMMC-only install on AGX Orin (no NVMe writes at all), use
`--storage emmc`. For Orin Nano, only NVMe is supported (the board has no
eMMC).

See [`docs/ARCHITECTURE.md`](ARCHITECTURE.md#agx-orin-two-device-flash-for-nvme-mode)
for the full breakdown.
