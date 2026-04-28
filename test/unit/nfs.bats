#!/usr/bin/env bats

load ../helpers/load

setup() {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/util.sh"
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/nfs.sh"

    JR_NFS_EXPORTS_DEST="${JR_TMPDIR}/etc/exports.d/jetson-restore.conf"
    JR_NFS_STATE_DIR="${JR_TMPDIR}/var/lib/jetson-restore"
    export JR_NFS_EXPORTS_DEST JR_NFS_STATE_DIR

    mkdir -p "$(dirname "${JR_NFS_EXPORTS_DEST}")" "${JR_NFS_STATE_DIR}"

    # Tests opt out of sudo.
    export JR_FS_WRITER=run_cmd
    export JR_SYSTEMCTL_STATE

    jr_use_stub sudo
    jr_use_stub tee
    jr_use_stub exportfs
    jr_use_stub systemctl
}

@test "install_nfs_export writes the snippet with @JR_EXPORT_PATH@ replaced" {
    install_nfs_export "${JR_REPO_ROOT}" "/srv/jetson/Linux_for_Tegra"
    grep -q '/srv/jetson/Linux_for_Tegra' "${JR_NFS_EXPORTS_DEST}"
    grep -q '192.168.55.0/24' "${JR_NFS_EXPORTS_DEST}"
}

@test "install_nfs_export runs exportfs -ra" {
    install_nfs_export "${JR_REPO_ROOT}" "/srv/jetson/Linux_for_Tegra"
    jr_read_stub_log
    [[ "${output}" == *exportfs\ -ra* ]]
}

@test "ensure_nfs_server_running starts nfs-server if inactive and creates marker" {
    JR_SYSTEMCTL_STATE="inactive"
    ensure_nfs_server_running
    jr_read_stub_log
    [[ "${output}" == *systemctl\ start\ nfs-server* ]]
    [ -f "${JR_NFS_STATE_DIR}/nfs-server-started-by-us" ]
}

@test "ensure_nfs_server_running is no-op when already active" {
    JR_SYSTEMCTL_STATE="active"
    ensure_nfs_server_running
    jr_read_stub_log
    [[ "${output}" != *systemctl\ start\ nfs-server* ]]
    [ ! -f "${JR_NFS_STATE_DIR}/nfs-server-started-by-us" ]
}

@test "remove_nfs_export deletes snippet and runs exportfs -ra" {
    install_nfs_export "${JR_REPO_ROOT}" "/srv/jetson/Linux_for_Tegra"
    remove_nfs_export
    [ ! -f "${JR_NFS_EXPORTS_DEST}" ]
    jr_read_stub_log
    [[ "${output}" == *exportfs\ -ra* ]]
}

@test "stop_nfs_server_if_we_started_it stops and disables when marker present" {
    : >"${JR_NFS_STATE_DIR}/nfs-server-started-by-us"
    stop_nfs_server_if_we_started_it
    jr_read_stub_log
    [[ "${output}" == *systemctl\ disable\ --now\ nfs-server* ]]
    [ ! -f "${JR_NFS_STATE_DIR}/nfs-server-started-by-us" ]
}

@test "stop_nfs_server_if_we_started_it is no-op when no marker" {
    rm -f "${JR_NFS_STATE_DIR}/nfs-server-started-by-us"
    stop_nfs_server_if_we_started_it
    jr_read_stub_log
    [[ "${output}" != *systemctl\ disable* ]]
    [[ "${output}" != *systemctl\ stop* ]]
}
