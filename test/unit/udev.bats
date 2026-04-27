#!/usr/bin/env bats

load ../helpers/load

setup() {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/util.sh"
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/udev.sh"
    JR_UDEV_DEST="${JR_TMPDIR}/etc/udev/rules.d/70-jetson-restore.rules"
    export JR_UDEV_DEST
    export JR_FS_WRITER=run_cmd
    mkdir -p "$(dirname "${JR_UDEV_DEST}")"
    jr_use_stub sudo
    jr_use_stub udevadm
    jr_use_stub tee
}

@test "install_udev_rule writes the rule with @JR_GROUP@ replaced" {
    install_udev_rule "${JR_REPO_ROOT}" "wheel"
    grep -q 'GROUP="wheel"' "${JR_UDEV_DEST}"
    ! grep -q '@JR_GROUP@' "${JR_UDEV_DEST}"
}

@test "install_udev_rule reloads udev" {
    install_udev_rule "${JR_REPO_ROOT}" "wheel"
    jr_read_stub_log
    [[ "${output}" == *udevadm\ control\ --reload* ]]
}

@test "install_udev_rule is idempotent: second run does not re-reload" {
    install_udev_rule "${JR_REPO_ROOT}" "wheel"
    : >"${JR_STUB_LOG}"
    install_udev_rule "${JR_REPO_ROOT}" "wheel"
    jr_read_stub_log
    [[ "${output}" != *udevadm\ control\ --reload* ]]
}

@test "remove_udev_rule deletes the file when present" {
    install_udev_rule "${JR_REPO_ROOT}" "wheel"
    [ -f "${JR_UDEV_DEST}" ]
    remove_udev_rule
    [ ! -f "${JR_UDEV_DEST}" ]
}

@test "remove_udev_rule is a no-op when the file is absent" {
    run remove_udev_rule
    assert_success
}
