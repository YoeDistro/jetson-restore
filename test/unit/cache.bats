#!/usr/bin/env bats

load ../helpers/load

setup() {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/util.sh"
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/cache.sh"
    JR_WORKDIR="${JR_TMPDIR}/work"
    mkdir -p "${JR_WORKDIR}"
    export JR_WORKDIR JR_CURL_FAKE_BODY
    jr_use_stub curl
}

@test "download_artifact downloads to dest and renames .partial" {
    local content="hello-bsp"
    JR_CURL_FAKE_BODY="${content}"
    download_artifact \
        "${JR_WORKDIR}/cache/jp-6.2.1/Jetson_Linux.tbz2" \
        "https://example.invalid/bsp.tbz2"
    [ -f "${JR_WORKDIR}/cache/jp-6.2.1/Jetson_Linux.tbz2" ]
    [ ! -f "${JR_WORKDIR}/cache/jp-6.2.1/Jetson_Linux.tbz2.partial" ]
    assert_equal \
        "$(cat "${JR_WORKDIR}/cache/jp-6.2.1/Jetson_Linux.tbz2")" \
        "${content}"
}

@test "download_artifact skips download when dest already exists" {
    local content="hello-bsp"
    mkdir -p "${JR_WORKDIR}/cache/jp-6.2.1"
    printf '%s' "${content}" >"${JR_WORKDIR}/cache/jp-6.2.1/Jetson_Linux.tbz2"

    : >"${JR_STUB_LOG}"
    download_artifact \
        "${JR_WORKDIR}/cache/jp-6.2.1/Jetson_Linux.tbz2" \
        "https://example.invalid/bsp.tbz2"
    jr_read_stub_log
    [[ "${output}" != *curl* ]]
}
