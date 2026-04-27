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

## "nfs-server: Failed to start"

Some distros split NFS into multiple services. Try:

    sudo systemctl start nfs-kernel-server     # Ubuntu/Debian
    sudo systemctl start nfs-server.service    # Arch/RHEL

If both fail, install nfs-utils (Arch) or nfs-kernel-server (Ubuntu) and re-run.

## "checksum mismatch" on BSP download

NVIDIA occasionally rebuilds tarballs without changing the URL. If you trust the
source, update the SHA-256 in `jetpacks/<version>.conf` to match `sha256sum` of
the freshly downloaded file. Open an issue with the new value so we can update
the pinned config.
