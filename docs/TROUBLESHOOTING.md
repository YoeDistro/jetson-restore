# Troubleshooting

## "device not in recovery mode"

You forgot the recovery button combo, or the cable is data-only.

- **Orin Nano dev kit:** jumper pins 9–10 (FC REC + GND) on J14, then power on.
- **AGX Orin dev kit:** hold FORCE RECOVERY, press POWER, release after ~2 s.

Verify with `lsusb | grep 0955`.

## "another route exists for 192.168.55.0/24"

Something on your host is already using the RNDIS subnet — typically a VPN,
VirtualBox, or a Docker bridge. Either bring it down for the duration of the
flash, or change its subnet.

## Flash hangs at "Sending bootloader"

USB autosuspend is the usual cause. The udev rule disables it for VID 0955,
but if you're on a host where udev rules don't apply (some immutable distros),
disable it globally for the flash:

    echo -1 | sudo tee /sys/module/usbcore/parameters/autosuspend

## "nfs-server: Failed to start"

Some distros split NFS into multiple services. Try:

    sudo systemctl start nfs-kernel-server     # Ubuntu/Debian
    sudo systemctl start nfs-server.service    # Arch/RHEL

If both fail, install nfs-utils (Arch) or nfs-kernel-server (Ubuntu) and re-run.

## "checksum mismatch" on BSP download

NVIDIA occasionally rebuilds tarballs without changing the URL. If you trust
the source, update the SHA-256 in `jetpacks/<version>.conf` to match
`sha256sum` of the freshly downloaded file. Open an issue with the new value
so we can update the pinned config.
