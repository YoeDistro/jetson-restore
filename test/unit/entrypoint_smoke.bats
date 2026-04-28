#!/usr/bin/env bats

load ../helpers/load

@test "share/entrypoint.sh passes bash -n" {
    bash -n "${JR_REPO_ROOT}/share/entrypoint.sh"
}

@test "share/entrypoint.sh references NVIDIA's flash container" {
    # We don't ship our own image; the entrypoint runs inside NVIDIA's
    # jetson-linux-flash-x86. Make sure the doc comment stays in sync.
    grep -q 'jetson-linux-flash-x86' "${JR_REPO_ROOT}/share/entrypoint.sh"
}

@test "no container/ directory (we use NVIDIA's image; entrypoint lives in share/)" {
    [ ! -d "${JR_REPO_ROOT}/container" ]
}
