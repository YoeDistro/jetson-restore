#!/usr/bin/env bash
# Assemble and run the container.
set -euo pipefail

: "${JR_IMAGE:=ghcr.io/cbrake/jetson-restore}"

do_flash() {
    local runtime
    runtime="$(detect_runtime)"
    local image="${JR_IMAGE}:${JR_CONTAINER_TAG}"

    log_info "running container ${image}"
    "${runtime}" run --rm \
        --privileged \
        --net host \
        -v /dev/bus/usb:/dev/bus/usb \
        -v "${JR_WORKDIR}/Linux_for_Tegra:/Linux_for_Tegra" \
        "${image}" \
        "${JR_BOARD_ID}" "${JR_STORAGE}"
}
