#!/usr/bin/env bats

load ../helpers/load

setup() {
    for f in util config runtime flash; do
        # shellcheck source=/dev/null
        source "${JR_REPO_ROOT}/lib/${f}.sh"
    done
    jr_use_stub docker
    load_target  "${JR_REPO_ROOT}" "orin-nano-devkit"
    load_jetpack "${JR_REPO_ROOT}" "6.2.1"
    JR_WORKDIR="${JR_TMPDIR}/work"
    mkdir -p "${JR_WORKDIR}/Linux_for_Tegra"
    JR_STORAGE="${JR_DEFAULT_STORAGE}"
    export JR_WORKDIR JR_STORAGE
}

@test "container argv matches the pinned expected-orin-nano-argv.txt" {
    do_flash
    jr_read_stub_log
    local actual expected
    # Pin only the `run` invocation; pre-checks (image exists/pull/build) are
    # validated separately in flash.bats.
    actual="$(printf '%s' "${output}" | grep '^docker run' | sed "s|${JR_WORKDIR}|<WORKDIR>|g")"
    expected="$(cat "${JR_REPO_ROOT}/test/fixtures/expected-orin-nano-argv.txt")"
    assert_equal "${actual}" "${expected}"
}

@test "exports snippet for orin-nano matches expected-orin-nano-exports.txt" {
    local rendered actual expected
    rendered="$(sed "s|@JR_EXPORT_PATH@|${JR_WORKDIR}/Linux_for_Tegra|g" \
                    "${JR_REPO_ROOT}/share/jetson-restore.exports.tmpl")"
    actual="$(printf '%s' "${rendered}" | sed "s|${JR_WORKDIR}|<WORKDIR>|g")"
    expected="$(cat "${JR_REPO_ROOT}/test/fixtures/expected-orin-nano-exports.txt")"
    assert_equal "${actual}" "${expected}"
}
