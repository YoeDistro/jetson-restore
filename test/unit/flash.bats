#!/usr/bin/env bats

load ../helpers/load

setup() {
    for f in util config runtime flash; do
        # shellcheck source=/dev/null
        source "${JR_REPO_ROOT}/lib/${f}.sh"
    done
    jr_use_stub podman
    load_target "${JR_REPO_ROOT}" "orin-nano-devkit"
    load_jetpack "${JR_REPO_ROOT}" "6.2.1"
    JR_WORKDIR="${JR_TMPDIR}/work"
    mkdir -p "${JR_WORKDIR}/Linux_for_Tegra"
    export JR_WORKDIR
}

@test "do_flash invokes podman with the expected argv" {
    do_flash
    jr_read_stub_log
    [[ "${output}" == *podman\ run\ --rm\ --privileged* ]]
    [[ "${output}" == *--net\ host* ]]
    [[ "${output}" == */dev/bus/usb:/dev/bus/usb* ]]
    [[ "${output}" == *Linux_for_Tegra:/Linux_for_Tegra* ]]
    [[ "${output}" == *jetson-orin-nano-devkit\ nvme* ]]
}

@test "do_flash uses the JR_CONTAINER_TAG from the jetpack config" {
    JR_CONTAINER_TAG="6.2.1"
    do_flash
    jr_read_stub_log
    [[ "${output}" == *:6.2.1* ]]
}
