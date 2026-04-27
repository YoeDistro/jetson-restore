# Architecture

This file is a contributor-facing summary. The full design spec is in
[superpowers/specs/2026-04-27-jetson-restore-design.md](superpowers/specs/2026-04-27-jetson-restore-design.md).

## Two-layer design

- **Host wrapper (bash)** — preflight, NFS export, container orchestration.
- **Container (Ubuntu 22.04)** — NVIDIA's BSP toolchain, runs `l4t_initrd_flash.sh`.

The two share a bind-mounted `./work/` directory. The host NFS server exports
`./work/Linux_for_Tegra` to the recovery RNDIS subnet (`192.168.55.0/24`).
The Jetson's initrd, booted over USB, mounts that export to fetch the rootfs.

## Why not flash directly from Arch?

NVIDIA's `apply_binaries.sh` and friends assume Debian-isms (`dpkg`,
`start-stop-daemon`, exact qemu-user-static paths). Patching them is ongoing
maintenance. Containerizing the BSP toolchain pins those assumptions to a
known Ubuntu 22.04 layer and lets the host be anything.

## Why NFS, not just bind-mount?

JetPack 6 flashes via an initrd that boots on the device, brings up RNDIS over
USB, and mounts the rootfs from the host. The host has to expose the rootfs
over NFS for that mount to work. Bind-mounting works for the BSP scripts on
the host side but doesn't help the device — only NFS does.

## Adding a new target

Drop a file in `targets/<name>.conf` with the keys the existing files use
(see `targets/orin-nano-devkit.conf` for the canonical example). No code
change required.

## Adding a new JetPack version

Drop a file in `jetpacks/<version>.conf`. Build and push a new container
image tagged `:<version>`. Update `jetpacks/<version>.conf`'s
`JR_CONTAINER_TAG`.
