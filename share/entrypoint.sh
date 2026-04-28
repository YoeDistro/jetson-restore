#!/usr/bin/env bash
# Runs inside NVIDIA's jetson-linux-flash-x86 container, mounted in by
# lib/flash.sh via --entrypoint.
# Args: <board_id> <storage>
# Env:  JR_LINUX_FOR_TEGRA — host-and-container path of the Linux_for_Tegra
#                            tree (bind-mounted path-identical for nfs_check).
set -euo pipefail

BOARD_ID="${1:?board_id required (e.g., jetson-orin-nano-devkit)}"
STORAGE="${2:?storage required (e.g., nvme)}"

cd "${JR_LINUX_FOR_TEGRA}"

# Register qemu-aarch64 in binfmt_misc so apply_binaries.sh's chroot+dpkg
# step works on the aarch64 rootfs. NVIDIA's container ships qemu-user-static
# and binfmt-support but leaves the handler disabled and binfmt_misc unmounted.
# F flag pre-loads qemu-aarch64-static into kernel memory so the handler
# survives the chroot.
register_qemu_binfmt() {
    if [[ ! -e /proc/sys/fs/binfmt_misc/register ]]; then
        mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc
    fi
    [[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]] && return 0
    echo ':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\xfc\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:OCF' \
        >/proc/sys/fs/binfmt_misc/register
    echo "[entrypoint] registered qemu-aarch64 binfmt handler"
}
register_qemu_binfmt

# apply_binaries.sh is one-shot per BSP and mutates rootfs in place
# (mknod /dev/*, dpkg into chroot). DIRTY_MARKER lets the host's
# ensure_l4t_extracted detect a partial run and re-extract.
APPLIED_MARKER=".jr-binaries-applied"
DIRTY_MARKER=".jr-rootfs-dirty"
if [[ ! -f "${APPLIED_MARKER}" ]]; then
    echo "[entrypoint] running apply_binaries.sh (one-time per BSP)…"
    : >"${DIRTY_MARKER}"
    ./tools/l4t_flash_prerequisites.sh
    ./apply_binaries.sh
    : >"${APPLIED_MARKER}"
    rm -f "${DIRTY_MARKER}"
else
    echo "[entrypoint] BSP binaries already applied"
fi

case "${STORAGE}" in
    nvme)
        echo "[entrypoint] running l4t_initrd_flash.sh for ${BOARD_ID} on NVMe"
        exec ./tools/kernel_flash/l4t_initrd_flash.sh \
            --external-device nvme0n1p1 \
            -c ./tools/kernel_flash/flash_l4t_external.xml \
            --showlogs --network usb0 \
            "${BOARD_ID}" external
        ;;
    emmc)
        echo "[entrypoint] running flash.sh for ${BOARD_ID} on eMMC (mmcblk0p1)"
        exec ./flash.sh "${BOARD_ID}" mmcblk0p1
        ;;
    *)
        echo "[entrypoint] unsupported storage: ${STORAGE}" >&2
        exit 2
        ;;
esac
