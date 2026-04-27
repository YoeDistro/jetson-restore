#!/usr/bin/env bash
# Install/remove the NetworkManager keyfile for the recovery RNDIS interface.
set -euo pipefail

: "${JR_NM_DEST:=/etc/NetworkManager/system-connections/jetson-restore-rndis.nmconnection}"
: "${JR_FS_WRITER:=run_sudo}"

_nm_present() { command -v nmcli >/dev/null 2>&1; }
_nm_running() {
    _nm_present || return 1
    nmcli -t general status >/dev/null 2>&1
}

install_nm_keyfile() {
    local repo="$1" rndis_mac="$2"
    if ! _nm_present; then
        log_warn "NetworkManager not installed; skipping NM keyfile (this is fine on systemd-networkd hosts)"
        return 0
    fi
    local src="${repo}/share/jetson-restore.nmconnection.tmpl"
    local rendered
    rendered="$(sed "s|@JR_RNDIS_MAC@|${rndis_mac}|g" "${src}")"

    if [[ -f "${JR_NM_DEST}" ]] &&
        [[ "$(cat "${JR_NM_DEST}")" == "${rendered}" ]]; then
        log_info "NM keyfile already up to date"
        return 0
    fi

    log_info "installing NM keyfile to ${JR_NM_DEST}"
    local dest_dir
    dest_dir="$(dirname "${JR_NM_DEST}")"
    if [[ ! -d "${dest_dir}" ]]; then
        "${JR_FS_WRITER}" mkdir -p "${dest_dir}"
    fi
    printf '%s\n' "${rendered}" | "${JR_FS_WRITER}" tee "${JR_NM_DEST}" >/dev/null
    "${JR_FS_WRITER}" chmod 600 "${JR_NM_DEST}"
    if _nm_running; then
        "${JR_FS_WRITER}" nmcli connection reload
    else
        log_warn "NetworkManager not running; skipping 'nmcli connection reload' (keyfile will be loaded on next NM start)"
    fi
}

remove_nm_keyfile() {
    if [[ -f "${JR_NM_DEST}" ]]; then
        log_info "removing NM keyfile ${JR_NM_DEST}"
        "${JR_FS_WRITER}" rm -f "${JR_NM_DEST}"
        if _nm_running; then
            "${JR_FS_WRITER}" nmcli connection reload
        fi
    fi
}
