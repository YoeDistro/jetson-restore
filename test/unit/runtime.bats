#!/usr/bin/env bats

load ../helpers/load

setup() {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/util.sh"
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/runtime.sh"
}

@test "detect_runtime returns docker when it is on PATH" {
    jr_use_stub docker
    run detect_runtime
    assert_success
    assert_output "docker"
}

@test "detect_runtime fails clearly when docker is not installed" {
    local tools="${JR_TMPDIR}/minimal-tools"
    mkdir -p "${tools}"
    ln -sf /usr/bin/bash "${tools}/bash"
    run env -i PATH="${tools}" bash -c "
        source '${JR_REPO_ROOT}/lib/util.sh'
        source '${JR_REPO_ROOT}/lib/runtime.sh'
        detect_runtime
    "
    assert_failure 2
    [[ "${output}" == *docker\ not\ found* ]]
}
