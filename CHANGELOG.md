# Changelog

## Unreleased

Ready-for-tag checklist (v0.1.0):

- [ ] Run hardware E2E: `JETSON_RESTORE_E2E=1 ./test/e2e/orin-nano.sh` and `…/agx-orin.sh` against real dev kits.

Notable changes since plan:

- **Stop shipping our own container; use NVIDIA's `nvcr.io/nvidia/jetson-linux-flash-x86:r36.4` instead.** Earlier iterations built a custom Ubuntu 22.04 image and had to apt-install a long list of dependencies one debugging cycle at a time (cpp, libxml2-utils, openssh-client, udev, nfs-kernel-server, ...). NVIDIA already publishes [the exact image](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/jetson-linux-flash-x86) with all of that baked in. We now mount our entrypoint into their image at runtime instead. Removed `container/Containerfile` and the `make container` target entirely.
- **Container manages NFS, host doesn't.** Matches NVIDIA's documented usage. Removed host-side NFS install/start, the `/etc/exports.d/jetson-restore.conf` snippet, and `lib/nfs.sh`. Preflight now fails clearly if a host `nfs-server` is running (port-2049 collision with the container's nfsd via `--net host`).
- Path-identical bind mount of `Linux_for_Tegra` (host path == container path), required so NVIDIA's `nfs_check` prefix-matches against the active export list.
- Drop SHA-256 pinning of BSP/rootfs tarballs; trust HTTPS to `developer.nvidia.com` instead. NVIDIA does not publish sidecar checksums and the placeholders were a maintenance burden with no integrity gain over TLS.
- Fix `_check_one_jetson_only` preflight: filter VID 0955 device count by the target's recovery PID. AGX Orin in recovery exposes both `0955:7023` (APX) and `0955:7045` (Tegra On-Platform Operator) on the same physical port; the broad count tripped on a single board.
- Add `usb0` IP auto-assignment to the udev rule so hosts without NetworkManager get `192.168.55.1/24` on the Jetson's RNDIS gadget when it enumerates.

Initial release scope:

- Targets: Orin Nano dev kit, AGX Orin dev kit.
- Storage: NVMe (Orin Nano, AGX Orin) and eMMC (AGX Orin only).
- JetPack 6.2.1 / L4T R36.4.4.
- Stock NVIDIA L4T Ubuntu 22.04 sample rootfs.
- Architecture: bash host wrapper + NVIDIA's official `jetson-linux-flash-x86` container.
- Idempotent preflight; `jetson-restore uninstall` reverses host config.
