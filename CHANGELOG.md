# Changelog

## Unreleased

Ready-for-tag checklist (v0.1.0):

- [ ] Run hardware E2E: `JETSON_RESTORE_E2E=1 ./test/e2e/orin-nano.sh` and `…/agx-orin.sh` against real dev kits.
- [ ] Update `JR_IMAGE` default in `lib/flash.sh` if forking to a different ghcr.io owner.

Notable changes since plan:

- Drop SHA-256 pinning of BSP/rootfs tarballs; trust HTTPS to `developer.nvidia.com` instead. NVIDIA does not publish sidecar checksums and the placeholders were a maintenance burden with no integrity gain over TLS.
- Fix `_check_one_jetson_only` preflight: filter VID 0955 device count by the target's recovery PID. AGX Orin in recovery exposes both `0955:7023` (APX) and `0955:7045` (Tegra On-Platform Operator) on the same physical port; the broad count tripped on a single board.

Initial release scope:

- Targets: Orin Nano dev kit, AGX Orin dev kit.
- Storage: NVMe.
- JetPack 6.2.1 / L4T R36.4.4.
- Stock NVIDIA L4T Ubuntu 22.04 sample rootfs.
- Two-layer architecture: bash host wrapper + Ubuntu 22.04 container with NVIDIA's BSP toolchain.
- Idempotent preflight; `jetson-restore uninstall` reverses host config.
