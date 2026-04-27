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

@test "jetson-restore --storage emmc on agx-orin-devkit is accepted" {
    run "${JR_REPO_ROOT}/bin/jetson-restore" \
        --target agx-orin-devkit --storage emmc --dry-run
    assert_success
    [[ "${output}" == *DRY-RUN*emmc* ]]
}

@test "jetson-restore --storage emmc on orin-nano-devkit is rejected" {
    run "${JR_REPO_ROOT}/bin/jetson-restore" \
        --target orin-nano-devkit --storage emmc --dry-run
    assert_failure 2
    [[ "${output}" == *not\ supported\ on\ orin-nano-devkit* ]]
}

@test "jetson-restore --storage bogus is rejected" {
    run "${JR_REPO_ROOT}/bin/jetson-restore" \
        --target agx-orin-devkit --storage bogus --dry-run
    assert_failure 2
    [[ "${output}" == *not\ supported* ]]
}
