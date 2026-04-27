#!/usr/bin/env bash
# Orchestrate the 12 preflight checks/actions.
set -euo pipefail

: "${JR_RECOVERY_TIMEOUT:=30}"
: "${JR_RNDIS_MAC:=1a:2b:3c:4d:5e:6f}"
: "${JR_MIN_FREE_KB:=$((30 * 1024 * 1024))}" # 30 GB

_check_disk_space() {
    local workdir="$1"
    local avail_kb
    avail_kb="$(df --output=avail -k "${workdir}" | tail -n 1 | tr -d ' ')"
    if ((avail_kb < JR_MIN_FREE_KB)); then
        log_die "insufficient disk space in ${workdir}: ${avail_kb} KB free, need ${JR_MIN_FREE_KB} KB"
    fi
    log_info "disk space ok: ${avail_kb} KB free in ${workdir}"
}

_check_subnet_clear() {
    if ip route 2>/dev/null | grep -q '192\.168\.55\.0/24'; then
        log_die "another route exists for 192.168.55.0/24; reflash will conflict (VPN/VM?). Remove the route or change subnet."
    fi
}

_check_one_jetson_only() {
    local product_id="$1"
    local devices count
    mapfile -t devices < <(find_jetson_devices | awk -v pid="${product_id}" '$2 == pid')
    count="${#devices[@]}"
    if ((count > 1)) && [[ -z "${JR_DEVICE:-}" ]]; then
        log_die "multiple VID 0955:${product_id} devices attached; pick one with --device <bus>:<dev>"
    fi
}

_check_recovery_mode() {
    local product_id="$1"
    log_info "waiting for VID 0955:${product_id} (up to ${JR_RECOVERY_TIMEOUT}s)…"
    if ! wait_for_recovery "${product_id}" "${JR_RECOVERY_TIMEOUT}"; then
        log_err "device not in recovery mode (no 0955:${product_id} on USB)"
        log_err "${JR_RECOVERY_INSTRUCTIONS}"
        log_die "place the device in recovery mode and re-run"
    fi
}

# Run all 12 preflight checks/actions. Caller has already loaded:
#   target conf (JR_BOARD_ID, JR_USB_PRODUCT_ID, JR_RECOVERY_INSTRUCTIONS, …)
#   jetpack conf
#   set JR_WORKDIR to an absolute path
run_preflight() {
    log_info "preflight: container runtime"
    detect_runtime >/dev/null

    log_info "preflight: disk space"
    _check_disk_space "${JR_WORKDIR}"

    log_info "preflight: nfs-server"
    ensure_nfs_server_running

    log_info "preflight: nfs export"
    install_nfs_export "${JR_REPO_ROOT}" "${JR_WORKDIR}/Linux_for_Tegra"

    log_info "preflight: udev rule"
    install_udev_rule "${JR_REPO_ROOT}" "$(id -gn)"

    log_info "preflight: NetworkManager keyfile"
    install_nm_keyfile "${JR_REPO_ROOT}" "${JR_RNDIS_MAC}"

    log_info "preflight: subnet not in use"
    _check_subnet_clear

    log_info "preflight: at most one Jetson attached"
    _check_one_jetson_only "${JR_USB_PRODUCT_ID}"

    log_info "preflight: device in recovery mode"
    _check_recovery_mode "${JR_USB_PRODUCT_ID}"

    log_info "preflight: complete"
}
