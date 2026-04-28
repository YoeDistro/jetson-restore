#!/usr/bin/env bash
# Assemble and run the container.
set -euo pipefail

: "${JR_IMAGE:=ghcr.io/cbrake/jetson-restore}"

# Ensure the flash container image is available locally. Try registry pull
# first; on failure fall back to building from container/Containerfile.
_ensure_image() {
    local runtime="$1" image="$2"
    if "${runtime}" image exists "${image}" 2>/dev/null; then
        return 0
    fi
    log_info "pulling ${image}"
    if "${runtime}" pull "${image}" 2>/dev/null; then
        return 0
    fi
    log_info "registry pull failed; building ${image} locally from ${JR_REPO_ROOT}/container/"
    "${runtime}" build -t "${image}" \
        -f "${JR_REPO_ROOT}/container/Containerfile" \
        "${JR_REPO_ROOT}/container/"
}

do_flash() {
    local runtime
    runtime="$(detect_runtime)"
    local image="${JR_IMAGE}:${JR_CONTAINER_TAG}"

    _ensure_image "${runtime}" "${image}"

    log_info "running container ${image}"
    # /run/udev is needed by l4t_initrd_flash.sh's container-awareness check:
    # it calls `udevadm info` on each VID 0955 device and skips any whose
    # DEVNAME isn't accessible. Without the host udev database mounted in,
    # the lookup returns empty and the script silently reports "No devices
    # to flash" even when the Jetson is plugged in and in recovery mode.
    "${runtime}" run --rm \
        --privileged \
        --net host \
        -v /dev/bus/usb:/dev/bus/usb \
        -v /run/udev:/run/udev:ro \
        -v "${JR_WORKDIR}/Linux_for_Tegra:/Linux_for_Tegra" \
        "${image}" \
        "${JR_BOARD_ID}" "${JR_STORAGE}"
}
