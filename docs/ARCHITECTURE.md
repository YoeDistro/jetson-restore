# Architecture

This file describes the current architecture.

## Two-layer design

- **Host wrapper (bash)** — preflight (udev rule, NM keyfile, recovery-mode
  detection), BSP cache management, container orchestration.
- **NVIDIA's
  [`nvcr.io/nvidia/jetson-linux-flash-x86`](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/jetson-linux-flash-x86)
  container** — Ubuntu 20.04 with every dependency NVIDIA's flash tools need
  (`qemu-user-static`, `binfmt-support`, `nfs-kernel-server`, `libxml2-utils`,
  `cpp`, `openssh-client`, `udev`). We don't ship our own image; we mount our
  entrypoint script in at runtime.

The two share a bind-mounted `./work/Linux_for_Tegra/` directory at the **same
path** inside the container as on the host (e.g.
`/scratch/.../work/Linux_for_Tegra:/scratch/.../work/Linux_for_Tegra`). This
matters for NFS — see below.

## Why not flash directly from Arch (or NixOS, Fedora, …)?

NVIDIA's `apply_binaries.sh` and friends assume Debian-isms (`dpkg`,
`start-stop-daemon`, `service`, exact `qemu-aarch64-static` paths). Patching
them is ongoing maintenance. Pushing all of that into NVIDIA's own image makes
us their tested configuration.

## Why NFS, not just bind-mount?

JetPack 6's NVMe flash flow boots an initrd on the Jetson, brings up RNDIS over
USB, and **mounts the rootfs from the host over NFS** to copy it onto the target
storage. Bind-mounting works for the BSP scripts on the host side but doesn't
help the device — only NFS over RNDIS does.

## NFS: container-managed, not host-managed

NVIDIA's `l4t_initrd_flash.sh` manages NFS itself when it detects it's running
inside Docker (the `is_inside_docker()` function in
`tools/kernel_flash/l4t_network_flash.func`). Specifically:

- The container's `network_prerequisite()` writes its own `/etc/exports` and
  runs `service nfs-kernel-server restart`.
- Because we run `--privileged --net host`, that "container" `nfsd` is actually
  controlling the host kernel's single `nfsd` instance and binding to the host's
  port 2049.
- The Jetson, via RNDIS, hits `192.168.55.1` on the host and mounts.

This is why preflight refuses to run if the host's `nfs-server` is active: the
container's invocation would collide on port 2049. We don't install or start NFS
on the host at all.

### Two non-obvious mount requirements

1. **Path-identical bind mount** of `Linux_for_Tegra`. NVIDIA's `nfs_check()`
   does prefix-matching of the BSP path against the active exports list. If the
   host path differs from the container path, the prefix-match fails and the
   script bails with "seems to be not exported by nfs server."
2. **`/run/rpcbind.sock` from the host.** With `--net host`, the host's
   `rpcbind` already owns port 111. The container's bare `rpcbind` invocation in
   NVIDIA's script silently runs as a zombie. The container's `rpc.mountd` then
   registers via local Unix socket — to the _zombie_ rpcbind. Bind-mounting the
   host's socket makes mountd register with the _real_ rpcbind so
   `showmount -e localhost` sees it.

### `usb0` IP assignment

The Jetson's RNDIS gadget enumerates as `usb0` on the host with no auto-assigned
IP. Our udev rule (`share/70-jetson-restore.rules`) fires on
`KERNEL=="usb0", ACTION=="add"` and runs
`ip addr add 192.168.55.1/24 dev %k && ip link set %k up`. This is
NetworkManager-independent — works on hosts running NM, systemd-networkd, or
nothing at all.

## AGX Orin: two-device flash for "NVMe" mode

The AGX Orin Devkit's BootROM only knows how to read QSPI flash and eMMC; NVMe
isn't visible to BootROM. So even when the user picks `--storage nvme`, the boot
chain has to live on internal storage. NVIDIA's
`l4t_initrd_flash.sh ... external` reflects this:

| Where                   | What lands                                                          |
| ----------------------- | ------------------------------------------------------------------- |
| QSPI flash (on-package) | MB1, BCT, etc.                                                      |
| eMMC                    | Bootloader, kernel `Image`, dtb, ESP, recovery, **fallback rootfs** |
| NVMe (`/dev/nvme0n1p1`) | Primary rootfs the system boots into                                |

Both eMMC and NVMe end up with a populated `APP` partition: NVMe is the primary,
eMMC is a fallback so the system can still come up if NVMe is missing or corrupt
at boot. Output during flash shows `Formatting APP partition /dev/mmcblk0p1 ...`
_and_ `Formatting APP partition /dev/nvme0n1p1 ...`, and
`Successfully flashed the eMMC.` appears mid-run — the script then proceeds to
the NVMe half.

For Orin Nano (no eMMC), `--storage nvme` puts everything on NVMe.

For AGX Orin `--storage emmc`, `flash.sh BOARD mmcblk0p1` runs and everything
(boot chain + rootfs) goes on eMMC only.

## What `apply_binaries.sh` does

A one-shot rootfs preparation step (NVIDIA's, runs inside the container). Takes
the freshly-extracted sample rootfs and the BSP payload and:

1. Unpacks NVIDIA's L4T `.deb` packages into the rootfs (CUDA stubs, multimedia
   libs, NVIDIA-customized boot binaries, kernel modules, firmware blobs) via
   chroot + `qemu-aarch64-static`.
2. Runs `nv_customize_rootfs.sh` — sets up `/etc/nv_tegra_release`,
   kernel-symlinks, default systemd targets, etc.
3. Rebuilds `boot/initrd` with NVIDIA's bootloader hooks.

After it succeeds the rootfs is "Jetson-ready" and `flash.sh` /
`l4t_initrd_flash.sh` can write it. We mark `.jr-binaries-applied` so re-runs
skip it (it's idempotent but slow).

## Adding a new target

Drop a file in `targets/<name>.conf` with the keys the existing files use (see
`targets/orin-nano-devkit.conf` for the canonical example). No code change
required.

## Adding a new JetPack version

Drop a file in `jetpacks/<version>.conf`. Update `JR_FLASH_IMAGE` to point at
the matching NVIDIA flash container tag (e.g. `r36.4` pairs with L4T R36.4.x).
NVIDIA publishes new tags on
[NGC](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/jetson-linux-flash-x86).
