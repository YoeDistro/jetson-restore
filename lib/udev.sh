#!/usr/bin/env bash
# Install/remove the udev rule for VID 0955.
#
# In production, bin/jetson-restore sets JR_FS_WRITER=run_sudo so the file
# write goes through sudo via the `tee` indirection. In tests, JR_UDEV_DEST is
# in a temp dir the test user owns, so the direct write succeeds without sudo.
set -euo pipefail

: "${JR_UDEV_DEST:=/etc/udev/rules.d/70-jetson-restore.rules}"
: "${JR_FS_WRITER:=run_cmd}"

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
