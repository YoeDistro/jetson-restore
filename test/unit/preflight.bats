#!/usr/bin/env bats

load ../helpers/load

setup() {
    # Bring in everything preflight depends on.
    for f in util config runtime recovery udev netmgr nfs cache preflight; do
        # shellcheck source=/dev/null
        source "${JR_REPO_ROOT}/lib/${f}.sh"
    done

    # Per-test stub roots.
    JR_UDEV_DEST="${JR_TMPDIR}/etc/udev/rules.d/70-jetson-restore.rules"
    JR_NM_DEST="${JR_TMPDIR}/etc/NetworkManager/system-connections/jetson-restore-rndis.nmconnection"
    JR_NFS_EXPORTS_DEST="${JR_TMPDIR}/etc/exports.d/jetson-restore.conf"
    JR_NFS_STATE_DIR="${JR_TMPDIR}/var/lib/jetson-restore"
    JR_WORKDIR="${JR_TMPDIR}/work"
    export JR_UDEV_DEST JR_NM_DEST JR_NFS_EXPORTS_DEST JR_NFS_STATE_DIR JR_WORKDIR

    mkdir -p "${JR_WORKDIR}"

    # Tests opt out of sudo.
    export JR_FS_WRITER=run_cmd

    # Stubs we always want active.
    jr_use_stub sudo
    jr_use_stub tee
    jr_use_stub udevadm
    jr_use_stub nmcli
    jr_use_stub exportfs
    jr_use_stub systemctl
    jr_use_stub chmod
    jr_use_stub lsusb
    jr_use_stub docker
    jr_use_stub df
    jr_use_stub ip

    export JR_LSUSB_OUTPUT
    export JR_SYSTEMCTL_STATE
    export JR_DF_FREE_KB
    export JR_IP_ROUTE_OUT

    # Load configs the entrypoint normally loads.
    load_target  "${JR_REPO_ROOT}" "orin-nano-devkit"
    load_jetpack "${JR_REPO_ROOT}" "6.2.1"
}

@test "run_preflight succeeds with happy-path stubs" {
    JR_LSUSB_OUTPUT="Bus 003 Device 042: ID 0955:7e19 NVIDIA Corp. APX"
    JR_SYSTEMCTL_STATE="active"
    JR_DF_FREE_KB=$((40 * 1024 * 1024))  # 40 GB free
    JR_IP_ROUTE_OUT=""
    run run_preflight
    assert_success
}

@test "run_preflight fails when device is not in recovery mode" {
    JR_LSUSB_OUTPUT=""
    JR_SYSTEMCTL_STATE="active"
    JR_DF_FREE_KB=$((40 * 1024 * 1024))
    JR_IP_ROUTE_OUT=""
    JR_RECOVERY_TIMEOUT=1
    run run_preflight
    assert_failure 2
    [[ "${output}" == *not\ in\ recovery\ mode* ]]
}

@test "run_preflight fails when disk space is below 30 GB" {
    JR_LSUSB_OUTPUT="Bus 003 Device 042: ID 0955:7e19 NVIDIA Corp. APX"
    JR_SYSTEMCTL_STATE="active"
    JR_DF_FREE_KB=$((10 * 1024 * 1024))  # 10 GB
    JR_IP_ROUTE_OUT=""
    run run_preflight
    assert_failure 2
    [[ "${output}" == *insufficient\ disk\ space* ]]
}

@test "run_preflight succeeds when target Jetson exposes a second non-recovery 0955 device" {
    # AGX Orin in recovery mode exposes 0955:7023 (APX) and 0955:7045
    # (Tegra On-Platform Operator) on the same physical port. The "at most one
    # Jetson" check must filter by the target's recovery product ID.
    load_target "${JR_REPO_ROOT}" "agx-orin-devkit"
    JR_LSUSB_OUTPUT="\
Bus 001 Device 031: ID 0955:7045 NVIDIA Corp. Tegra On-Platform Operator
Bus 001 Device 032: ID 0955:7023 NVIDIA Corp. APX"
    JR_SYSTEMCTL_STATE="active"
    JR_DF_FREE_KB=$((40 * 1024 * 1024))
    JR_IP_ROUTE_OUT=""
    run run_preflight
    assert_success
}

@test "run_preflight fails when two Jetsons of the target model are in recovery" {
    JR_LSUSB_OUTPUT="\
Bus 003 Device 042: ID 0955:7e19 NVIDIA Corp. APX
Bus 004 Device 015: ID 0955:7e19 NVIDIA Corp. APX"
    JR_SYSTEMCTL_STATE="active"
    JR_DF_FREE_KB=$((40 * 1024 * 1024))
    JR_IP_ROUTE_OUT=""
    run run_preflight
    assert_failure 2
    [[ "${output}" == *multiple\ VID\ 0955:7e19\ devices* ]]
}

@test "run_preflight is idempotent on the second invocation" {
    JR_LSUSB_OUTPUT="Bus 003 Device 042: ID 0955:7e19 NVIDIA Corp. APX"
    JR_SYSTEMCTL_STATE="active"
    JR_DF_FREE_KB=$((40 * 1024 * 1024))
    JR_IP_ROUTE_OUT=""
    run_preflight
    : >"${JR_STUB_LOG}"
    run_preflight
    jr_read_stub_log
    [[ "${output}" != *udevadm\ control\ --reload* ]]
    [[ "${output}" != *nmcli\ connection\ reload* ]]
}
