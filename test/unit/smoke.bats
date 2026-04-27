#!/usr/bin/env bats

load ../helpers/load

@test "bats helpers load and JR_REPO_ROOT is set" {
    [ -n "${JR_REPO_ROOT}" ]
    [ -d "${JR_REPO_ROOT}" ]
    [ -f "${JR_REPO_ROOT}/Makefile" ]
}
