#!/usr/bin/env bats

load ../helpers/load

setup() {
    for f in util udev netmgr uninstall; do
        # shellcheck source=/dev/null
        source "${JR_REPO_ROOT}/lib/${f}.sh"
    done
    JR_UDEV_DEST="${JR_TMPDIR}/etc/udev/rules.d/70-jetson-restore.rules"
    JR_NM_DEST="${JR_TMPDIR}/etc/NetworkManager/system-connections/jetson-restore-rndis.nmconnection"
    export JR_UDEV_DEST JR_NM_DEST
    mkdir -p "$(dirname "${JR_UDEV_DEST}")" "$(dirname "${JR_NM_DEST}")"

    # Tests opt out of sudo.
    export JR_FS_WRITER=run_cmd

    jr_use_stub sudo
    jr_use_stub udevadm
    jr_use_stub nmcli
}

@test "do_uninstall removes udev rule and NM keyfile" {
    : >"${JR_UDEV_DEST}"
    : >"${JR_NM_DEST}"

    do_uninstall

    [ ! -f "${JR_UDEV_DEST}" ]
    [ ! -f "${JR_NM_DEST}" ]
}

@test "do_uninstall is a no-op when nothing was installed" {
    do_uninstall
    [ ! -f "${JR_UDEV_DEST}" ]
    [ ! -f "${JR_NM_DEST}" ]
}
