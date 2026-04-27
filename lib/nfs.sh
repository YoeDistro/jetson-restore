#!/usr/bin/env bash
# Manage the NFS exports.d snippet and nfs-server state.
set -euo pipefail

: "${JR_NFS_EXPORTS_DEST:=/etc/exports.d/jetson-restore.conf}"
: "${JR_NFS_STATE_DIR:=/var/lib/jetson-restore}"
: "${JR_FS_WRITER:=run_sudo}"

_marker_file() { echo "${JR_NFS_STATE_DIR}/nfs-server-started-by-us"; }

install_nfs_export() {
    local repo="$1" export_path="$2"
    local src="${repo}/share/jetson-restore.exports.tmpl"
    local rendered
    rendered="$(sed "s|@JR_EXPORT_PATH@|${export_path}|g" "${src}")"

    if [[ -f "${JR_NFS_EXPORTS_DEST}" ]] &&
        [[ "$(cat "${JR_NFS_EXPORTS_DEST}")" == "${rendered}" ]]; then
        log_info "NFS export already up to date"
        return 0
    fi

    log_info "installing NFS export ${JR_NFS_EXPORTS_DEST} → ${export_path}"
    local dest_dir
    dest_dir="$(dirname "${JR_NFS_EXPORTS_DEST}")"
    if [[ ! -d "${dest_dir}" ]]; then
        "${JR_FS_WRITER}" mkdir -p "${dest_dir}"
    fi
    printf '%s\n' "${rendered}" | "${JR_FS_WRITER}" tee "${JR_NFS_EXPORTS_DEST}" >/dev/null
    "${JR_FS_WRITER}" exportfs -ra
}

remove_nfs_export() {
    if [[ -f "${JR_NFS_EXPORTS_DEST}" ]]; then
        log_info "removing NFS export ${JR_NFS_EXPORTS_DEST}"
        "${JR_FS_WRITER}" rm -f "${JR_NFS_EXPORTS_DEST}"
        "${JR_FS_WRITER}" exportfs -ra
    fi
}

ensure_nfs_server_running() {
    local state
    state="$(systemctl is-active nfs-server 2>/dev/null || true)"
    if [[ "${state}" == "active" ]]; then
        log_info "nfs-server already active"
        return 0
    fi
    log_warn "starting nfs-server (will remain running; 'systemctl disable --now nfs-server' to stop)"
    "${JR_FS_WRITER}" mkdir -p "${JR_NFS_STATE_DIR}"
    "${JR_FS_WRITER}" tee "$(_marker_file)" </dev/null >/dev/null
    "${JR_FS_WRITER}" systemctl start nfs-server
    "${JR_FS_WRITER}" systemctl enable nfs-server
}

stop_nfs_server_if_we_started_it() {
    if [[ -f "$(_marker_file)" ]]; then
        log_info "stopping nfs-server (we started it earlier)"
        "${JR_FS_WRITER}" systemctl stop nfs-server
        "${JR_FS_WRITER}" rm -f "$(_marker_file)"
    fi
}
