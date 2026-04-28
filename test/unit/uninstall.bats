#!/usr/bin/env bats

load ../helpers/load

setup() {
    for f in util udev netmgr nfs uninstall; do
        # shellcheck source=/dev/null
        source "${JR_REPO_ROOT}/lib/${f}.sh"
    done
    JR_UDEV_DEST="${JR_TMPDIR}/etc/udev/rules.d/70-jetson-restore.rules"
    JR_NM_DEST="${JR_TMPDIR}/etc/NetworkManager/system-connections/jetson-restore-rndis.nmconnection"
    JR_NFS_EXPORTS_DEST="${JR_TMPDIR}/etc/exports.d/jetson-restore.conf"
    JR_NFS_STATE_DIR="${JR_TMPDIR}/var/lib/jetson-restore"
    export JR_UDEV_DEST JR_NM_DEST JR_NFS_EXPORTS_DEST JR_NFS_STATE_DIR
    mkdir -p "$(dirname "${JR_UDEV_DEST}")" \
             "$(dirname "${JR_NM_DEST}")" \
             "$(dirname "${JR_NFS_EXPORTS_DEST}")" \
             "${JR_NFS_STATE_DIR}"

    # Tests opt out of sudo.
    export JR_FS_WRITER=run_cmd

    jr_use_stub sudo
    jr_use_stub tee
    jr_use_stub udevadm
    jr_use_stub nmcli
    jr_use_stub exportfs
    jr_use_stub systemctl
}

@test "do_uninstall removes udev, NM, exports, and disables nfs only if we enabled it" {
    : >"${JR_UDEV_DEST}"
    : >"${JR_NM_DEST}"
    : >"${JR_NFS_EXPORTS_DEST}"
    : >"${JR_NFS_STATE_DIR}/nfs-server-started-by-us"

    do_uninstall

    [ ! -f "${JR_UDEV_DEST}" ]
    [ ! -f "${JR_NM_DEST}" ]
    [ ! -f "${JR_NFS_EXPORTS_DEST}" ]

    jr_read_stub_log
    [[ "${output}" == *systemctl\ disable\ --now\ nfs-server* ]]
}

@test "do_uninstall does not touch nfs-server when no marker is present" {
    do_uninstall
    jr_read_stub_log
    [[ "${output}" != *systemctl\ disable* ]]
    [[ "${output}" != *systemctl\ stop* ]]
}
