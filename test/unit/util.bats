#!/usr/bin/env bats

load ../helpers/load

setup() {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/util.sh"
    JR_NO_SUDO=0
    JR_DRY_RUN=0
}

@test "log_info writes to stderr with INFO prefix" {
    run --separate-stderr log_info "hello"
    assert_equal "${stderr}" "[INFO] hello"
}

@test "log_die writes ERROR to stderr and exits 2" {
    run log_die "boom"
    assert_failure 2
    [[ "${output}" == *ERROR*boom* ]]
}

@test "run_sudo invokes sudo with given argv when JR_NO_SUDO=0" {
    jr_use_stub sudo
    JR_NO_SUDO=0 run_sudo systemctl start nfs-server
    jr_read_stub_log
    assert_output "sudo systemctl start nfs-server"
}

@test "run_sudo with JR_NO_SUDO=1 records command and does not invoke sudo" {
    jr_use_stub sudo
    JR_NO_SUDO=1 JR_SUDO_QUEUE_FILE="${JR_TMPDIR}/queue.sh" \
        run_sudo systemctl start nfs-server
    [ ! -s "${JR_STUB_LOG}" ]
    grep -q 'systemctl start nfs-server' "${JR_TMPDIR}/queue.sh"
}

@test "run_cmd with JR_DRY_RUN=1 prints command and does not execute" {
    jr_use_stub sudo
    JR_DRY_RUN=1 run_cmd echo "should-not-run"
    [ ! -s "${JR_STUB_LOG}" ]
}
