#!/usr/bin/env bats

load ../helpers/load

setup() {
    for f in util config runtime flash; do
        # shellcheck source=/dev/null
        source "${JR_REPO_ROOT}/lib/${f}.sh"
    done
    jr_use_stub docker
    load_target "${JR_REPO_ROOT}" "orin-nano-devkit"
    load_jetpack "${JR_REPO_ROOT}" "6.2.1"
    JR_WORKDIR="${JR_TMPDIR}/work"
    mkdir -p "${JR_WORKDIR}/Linux_for_Tegra"
    JR_STORAGE="${JR_DEFAULT_STORAGE}"
    export JR_WORKDIR JR_STORAGE
}

@test "do_flash invokes docker with the expected argv" {
    do_flash
    jr_read_stub_log
    [[ "${output}" == *docker\ run\ --rm\ --privileged* ]]
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

@test "do_flash builds the image locally when registry pull fails" {
    # Replace the always-success docker stub: fail for 'image exists' (not
    # present locally) and 'pull' (registry 403); succeed for build/run.
    local stubs_active="${JR_TMPDIR}/stubs-active"
    rm -f "${stubs_active}/docker"
    cat >"${stubs_active}/docker" <<'STUB'
#!/usr/bin/env bash
echo "docker $*" >>"${JR_STUB_LOG}"
case "$1" in
    image) exit 1 ;;
    pull)  exit 1 ;;
    *)     exit 0 ;;
esac
STUB
    chmod +x "${stubs_active}/docker"

    do_flash
    jr_read_stub_log
    [[ "${output}" == *docker\ build\ -t\ ghcr.io/cbrake/jetson-restore:* ]]
    [[ "${output}" == *docker\ run\ --rm* ]]
}
