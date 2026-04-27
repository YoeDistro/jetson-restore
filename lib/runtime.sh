#!/usr/bin/env bash
# Podman/docker abstraction.
set -euo pipefail

detect_runtime() {
    if command -v podman >/dev/null 2>&1; then
        echo "podman"
        return 0
    fi
    if command -v docker >/dev/null 2>&1; then
        echo "docker"
        return 0
    fi
    log_die "neither podman nor docker found in PATH; install one and retry"
}

# Build the container run argv. Echoes a NUL-separated argv that the caller
# pipes into `xargs -0` or reads with mapfile -d ''.
build_run_argv() {
    local runtime="$1" image="$2" workdir="$3"
    shift 3
    # Remaining args are passed to the container entrypoint.
    local argv=(
        "${runtime}" run --rm
        --privileged
        --net host
        -v /dev/bus/usb:/dev/bus/usb
        -v "${workdir}/Linux_for_Tegra:/Linux_for_Tegra"
        "${image}"
        "$@"
    )
    printf '%s\0' "${argv[@]}"
}
