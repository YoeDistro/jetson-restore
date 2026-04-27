#!/usr/bin/env bash
# Install/remove the udev rule for VID 0955.
#
# JR_FS_WRITER defaults to run_sudo so production file writes go through sudo.
# Tests set JR_FS_WRITER=run_cmd and point JR_UDEV_DEST at a temp dir the
# test user owns, so no privilege escalation is required.
set -euo pipefail

: "${JR_UDEV_DEST:=/etc/udev/rules.d/70-jetson-restore.rules}"
: "${JR_FS_WRITER:=run_sudo}"

install_udev_rule() {
    local repo="$1" group="$2"
    local src="${repo}/share/70-jetson-restore.rules"
    local rendered
    rendered="$(sed "s|@JR_GROUP@|${group}|g" "${src}")"

    if [[ -f "${JR_UDEV_DEST}" ]] &&
        [[ "$(cat "${JR_UDEV_DEST}")" == "${rendered}" ]]; then
        log_info "udev rule already up to date"
        return 0
    fi

    log_info "installing udev rule to ${JR_UDEV_DEST}"
    local dest_dir
    dest_dir="$(dirname "${JR_UDEV_DEST}")"
    if [[ ! -d "${dest_dir}" ]]; then
        "${JR_FS_WRITER}" mkdir -p "${dest_dir}"
    fi
    printf '%s\n' "${rendered}" | "${JR_FS_WRITER}" tee "${JR_UDEV_DEST}" >/dev/null
    "${JR_FS_WRITER}" udevadm control --reload
    "${JR_FS_WRITER}" udevadm trigger --subsystem-match=usb
}

remove_udev_rule() {
    if [[ -f "${JR_UDEV_DEST}" ]]; then
        log_info "removing udev rule ${JR_UDEV_DEST}"
        "${JR_FS_WRITER}" rm -f "${JR_UDEV_DEST}"
        "${JR_FS_WRITER}" udevadm control --reload
    fi
}
