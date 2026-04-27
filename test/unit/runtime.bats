#!/usr/bin/env bats

load ../helpers/load

setup() {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/util.sh"
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/runtime.sh"
}

@test "detect_runtime prefers podman when both are installed" {
    jr_use_stub podman
    jr_use_stub docker
    run detect_runtime
    assert_success
    assert_output "podman"
}

@test "detect_runtime falls back to docker when podman is absent" {
    # Use a subprocess with an explicit minimal PATH so the real /usr/bin/podman
    # on the host can't leak in. Without this, a host that has podman installed
    # would always satisfy `command -v podman` even when the test's intent is
    # that podman is not on PATH.
    local stubs="${JR_TMPDIR}/runtime-only-docker"
    mkdir -p "${stubs}"
    ln -sf "${JR_REPO_ROOT}/test/helpers/stubs/docker" "${stubs}/docker"
    # Provide bash in the PATH without exposing /usr/bin/podman.
    ln -sf /usr/bin/bash "${stubs}/bash"
    local stub_log="${JR_TMPDIR}/stub-docker-fallback.log"
    touch "${stub_log}"
    run env -i PATH="${stubs}" JR_STUB_LOG="${stub_log}" bash -c "
        source '${JR_REPO_ROOT}/lib/util.sh'
        source '${JR_REPO_ROOT}/lib/runtime.sh'
        detect_runtime
    "
    assert_success
    assert_output "docker"
}

@test "detect_runtime fails clearly when neither is installed" {
    # Provide bash but not docker or podman.
    local tools="${JR_TMPDIR}/minimal-tools"
    mkdir -p "${tools}"
    ln -sf /usr/bin/bash "${tools}/bash"
    run env -i PATH="${tools}" bash -c "
        source '${JR_REPO_ROOT}/lib/util.sh'
        source '${JR_REPO_ROOT}/lib/runtime.sh'
        detect_runtime
    "
    assert_failure 2
    [[ "${output}" == *neither\ podman\ nor\ docker* ]]
}
