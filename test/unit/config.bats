#!/usr/bin/env bats

load ../helpers/load

setup() {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/util.sh"
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/config.sh"
}

@test "load_target reads orin-nano-devkit and sets JR_BOARD_ID" {
    load_target "${JR_REPO_ROOT}" "orin-nano-devkit"
    assert_equal "${JR_BOARD_ID}" "jetson-orin-nano-devkit"
    assert_equal "${JR_USB_PRODUCT_ID}" "7e19"
}

@test "load_target rejects an unknown target" {
    run load_target "${JR_REPO_ROOT}" "does-not-exist"
    assert_failure 2
    [[ "${output}" == *unknown\ target* ]]
}

@test "load_target rejects a target name with path traversal" {
    run load_target "${JR_REPO_ROOT}" "../../etc/passwd"
    assert_failure 2
    [[ "${output}" == *invalid\ target\ name* ]]
}

@test "load_jetpack reads 6.2.1 and sets JR_BSP_URL" {
    load_jetpack "${JR_REPO_ROOT}" "6.2.1"
    [[ "${JR_BSP_URL}" == https://* ]]
    # SHA-256 may still be the placeholder string in this commit.
    [ -n "${JR_BSP_SHA256}" ]
}

@test "list_targets prints all available target names" {
    run list_targets "${JR_REPO_ROOT}"
    assert_success
    [[ "${output}" == *orin-nano-devkit* ]]
    [[ "${output}" == *agx-orin-devkit* ]]
}
