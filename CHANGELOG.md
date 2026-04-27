# Changelog

## Unreleased

Ready-for-tag checklist (v0.1.0):

- [ ] Fill in real SHA-256 values in `jetpacks/6.2.1.conf` (currently `REPLACE_AT_IMPLEMENTATION_TIME`); the `jetpacks.bats` placeholder check enforces this.
- [ ] Run hardware E2E: `JETSON_RESTORE_E2E=1 ./test/e2e/orin-nano.sh` and `…/agx-orin.sh` against real dev kits.
- [ ] Update `JR_IMAGE` default in `lib/flash.sh` if forking to a different ghcr.io owner.

Initial release scope:

- Targets: Orin Nano dev kit, AGX Orin dev kit.
- Storage: NVMe.
- JetPack 6.2.1 / L4T R36.4.4.
- Stock NVIDIA L4T Ubuntu 22.04 sample rootfs.
- Two-layer architecture: bash host wrapper + Ubuntu 22.04 container with NVIDIA's BSP toolchain.
- Idempotent preflight; `jetson-restore uninstall` reverses host config.
- 65 bats unit tests (63 currently passing; 2 fail-by-design until SHA placeholders are filled in).
