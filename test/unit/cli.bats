#!/usr/bin/env bats

load ../helpers/load

@test "jetson-restore --help prints usage and exits 0" {
    run "${JR_REPO_ROOT}/bin/jetson-restore" --help
    assert_success
    [[ "${output}" == *Usage* ]]
    [[ "${output}" == *--target* ]]
    [[ "${output}" == *uninstall* ]]
}

@test "jetson-restore with no args prints usage and exits 2" {
    run "${JR_REPO_ROOT}/bin/jetson-restore"
    assert_failure 2
    [[ "${output}" == *Usage* ]]
}

@test "jetson-restore --target unknown errors clearly" {
    run "${JR_REPO_ROOT}/bin/jetson-restore" --target unknown-target
    assert_failure 2
    [[ "${output}" == *unknown\ target* ]]
}

@test "jetson-restore --dry-run prints commands without executing them" {
    run "${JR_REPO_ROOT}/bin/jetson-restore" \
        --target orin-nano-devkit --dry-run
    # Should mention the dry-run summary; should NOT actually run preflight or flash.
    [[ "${output}" == *DRY-RUN* ]]
}
