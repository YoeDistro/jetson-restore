#!/usr/bin/env bats

load ../helpers/load

setup() {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/util.sh"
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/netmgr.sh"

    JR_NM_DEST="${JR_TMPDIR}/etc/NetworkManager/system-connections/jetson-restore-rndis.nmconnection"
    export JR_NM_DEST
    mkdir -p "$(dirname "${JR_NM_DEST}")"

    # Tests opt out of sudo so the unprivileged user can run them.
    export JR_FS_WRITER=run_cmd

    jr_use_stub sudo
    jr_use_stub tee
    jr_use_stub nmcli
    jr_use_stub chmod
}

@test "install_nm_keyfile writes file with @JR_RNDIS_MAC@ replaced" {
    install_nm_keyfile "${JR_REPO_ROOT}" "1a:2b:3c:4d:5e:6f"
    grep -q 'mac-address=1a:2b:3c:4d:5e:6f' "${JR_NM_DEST}"
    ! grep -q '@JR_RNDIS_MAC@' "${JR_NM_DEST}"
}

@test "install_nm_keyfile sets file mode 0600 (NM requirement)" {
    install_nm_keyfile "${JR_REPO_ROOT}" "1a:2b:3c:4d:5e:6f"
    [ "$(stat -c %a "${JR_NM_DEST}")" = "600" ]
}

@test "install_nm_keyfile is idempotent" {
    install_nm_keyfile "${JR_REPO_ROOT}" "1a:2b:3c:4d:5e:6f"
    : >"${JR_STUB_LOG}"
    install_nm_keyfile "${JR_REPO_ROOT}" "1a:2b:3c:4d:5e:6f"
    jr_read_stub_log
    [[ "${output}" != *nmcli\ connection\ reload* ]]
}

@test "remove_nm_keyfile deletes the file" {
    install_nm_keyfile "${JR_REPO_ROOT}" "1a:2b:3c:4d:5e:6f"
    remove_nm_keyfile
    [ ! -f "${JR_NM_DEST}" ]
}

@test "install_nm_keyfile installs file but skips reload when NM not running" {
    JR_STUB_NMCLI_NOT_RUNNING=1 install_nm_keyfile "${JR_REPO_ROOT}" "1a:2b:3c:4d:5e:6f"
    [ -f "${JR_NM_DEST}" ]
    grep -q 'mac-address=1a:2b:3c:4d:5e:6f' "${JR_NM_DEST}"
    jr_read_stub_log
    [[ "${output}" != *"nmcli connection reload"* ]]
}

@test "remove_nm_keyfile skips reload when NM not running" {
    install_nm_keyfile "${JR_REPO_ROOT}" "1a:2b:3c:4d:5e:6f"
    : >"${JR_STUB_LOG}"
    JR_STUB_NMCLI_NOT_RUNNING=1 remove_nm_keyfile
    [ ! -f "${JR_NM_DEST}" ]
    jr_read_stub_log
    [[ "${output}" != *"nmcli connection reload"* ]]
}

@test "install_nm_keyfile is a no-op (warn) when nmcli is absent" {
    # Build a symlink farm that includes core utils but excludes nmcli so that
    # command -v nmcli returns false inside the subshell.
    local no_nmcli_bin="${JR_TMPDIR}/no-nmcli-bin"
    mkdir -p "${no_nmcli_bin}"
    for tool in bash sed cat mkdir rm stat dirname basename tee printf; do
        local real
        real="$(command -v "${tool}" 2>/dev/null)" || true
        if [[ -n "${real}" && "${real}" != */nmcli ]]; then
            ln -sf "${real}" "${no_nmcli_bin}/${tool}"
        fi
    done
    run env PATH="${no_nmcli_bin}" \
        JR_NM_DEST="${JR_NM_DEST}" \
        JR_FS_WRITER=run_cmd \
        bash -c "
            source '${JR_REPO_ROOT}/lib/util.sh'
            source '${JR_REPO_ROOT}/lib/netmgr.sh'
            install_nm_keyfile '${JR_REPO_ROOT}' '1a:2b:3c:4d:5e:6f'
        "
    assert_success
    [[ "${output}" == *NetworkManager\ not\ installed* ]]
}
