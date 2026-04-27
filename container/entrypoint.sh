#!/usr/bin/env bash
# Runs inside the jetson-restore container.
# Args: <board_id> <storage>
# Working directory: /Linux_for_Tegra (bind-mounted from host).
set -euo pipefail

BOARD_ID="${1:?board_id required (e.g., jetson-orin-nano-devkit)}"
STORAGE="${2:?storage required (e.g., nvme)}"

cd /Linux_for_Tegra

# Register qemu-aarch64 in binfmt_misc so dpkg etc. work inside the rootfs
# chroot during apply_binaries.sh. The F flag pre-loads qemu-aarch64-static
# into kernel memory so the handler survives the chroot (where the binary
# wouldn't otherwise be at the same path).
register_qemu_binfmt() {
    # The binfmt_misc filesystem isn't mounted in the container by default;
    # mount it (kernel-global, --privileged required).
    if [[ ! -e /proc/sys/fs/binfmt_misc/register ]]; then
        mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc
    fi
    if [[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
        return 0
    fi
    echo ':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\xfc\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:OCF' \
        >/proc/sys/fs/binfmt_misc/register
    echo "[container] registered qemu-aarch64 binfmt handler"
}
register_qemu_binfmt

# apply_binaries.sh is one-time per BSP version. Mark with a dotfile so
# repeat runs skip it.
APPLIED_MARKER=".jr-binaries-applied"
if [[ ! -f "${APPLIED_MARKER}" ]]; then
    echo "[container] running apply_binaries.sh (one-time per BSP)…"
    ./tools/l4t_flash_prerequisites.sh
    ./apply_binaries.sh
    : >"${APPLIED_MARKER}"
else
    echo "[container] BSP binaries already applied"
fi

case "${STORAGE}" in
    nvme)
        echo "[container] running l4t_initrd_flash.sh for ${BOARD_ID} on NVMe"
        exec ./tools/kernel_flash/l4t_initrd_flash.sh \
            --external-device nvme0n1p1 \
            -c ./tools/kernel_flash/flash_l4t_external.xml \
            --showlogs --network usb0 \
            "${BOARD_ID}" external
        ;;
    emmc)
        echo "[container] running flash.sh for ${BOARD_ID} on eMMC (mmcblk0p1)"
        exec ./flash.sh "${BOARD_ID}" mmcblk0p1
        ;;
    *)
        echo "[container] unsupported storage: ${STORAGE}" >&2
        exit 2
        ;;
esac
