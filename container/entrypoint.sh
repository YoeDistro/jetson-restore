#!/usr/bin/env bash
# Runs inside the jetson-restore container.
# Args: <board_id> <storage>
# Working directory: /Linux_for_Tegra (bind-mounted from host).
set -euo pipefail

BOARD_ID="${1:?board_id required (e.g., jetson-orin-nano-devkit)}"
STORAGE="${2:?storage required (e.g., nvme)}"

cd /Linux_for_Tegra

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
        external_device="nvme0n1p1"
        ;;
    *)
        echo "[container] unsupported storage: ${STORAGE}" >&2
        exit 2
        ;;
esac

echo "[container] running l4t_initrd_flash.sh for ${BOARD_ID} on ${STORAGE}"
exec ./tools/kernel_flash/l4t_initrd_flash.sh \
    --external-device "${external_device}" \
    -c ./tools/kernel_flash/flash_l4t_external.xml \
    --showlogs --network usb0 \
    "${BOARD_ID}" external
