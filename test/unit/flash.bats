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
    [[ "${output}" == */run/udev:/run/udev:ro* ]]
    [[ "${output}" == */run/rpcbind.sock:/run/rpcbind.sock* ]]
    [[ "${output}" == *Linux_for_Tegra:${JR_WORKDIR}/Linux_for_Tegra* ]]
    [[ "${output}" == *entrypoint.sh:/jr-entrypoint.sh:ro* ]]
    [[ "${output}" == *--entrypoint\ /jr-entrypoint.sh* ]]
    [[ "${output}" == *JR_LINUX_FOR_TEGRA=${JR_WORKDIR}/Linux_for_Tegra* ]]
    [[ "${output}" == *-e\ USER=root* ]]
    [[ "${output}" == *jetson-orin-nano-devkit\ nvme* ]]
}

@test "do_flash uses the JR_FLASH_IMAGE from the jetpack config" {
    do_flash
    jr_read_stub_log
    [[ "${output}" == *nvcr.io/nvidia/jetson-linux-flash-x86:r36.4* ]]
}

@test "do_flash fails clearly if NVIDIA's image cannot be pulled" {
    # Replace the always-success docker stub: fail 'image exists' (not local)
    # and 'pull' (registry unreachable). do_flash should propagate the error.
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

    run do_flash
    assert_failure
}
