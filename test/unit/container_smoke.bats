#!/usr/bin/env bats

load ../helpers/load

@test "container/entrypoint.sh passes bash -n" {
    bash -n "${JR_REPO_ROOT}/container/entrypoint.sh"
}

@test "Containerfile has FROM ubuntu:22.04" {
    grep -E '^FROM\s+docker\.io/library/ubuntu:22\.04$' \
        "${JR_REPO_ROOT}/container/Containerfile"
}
