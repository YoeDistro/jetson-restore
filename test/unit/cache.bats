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

@test "download_artifact downloads, verifies, and renames on sha256 match" {
    local content="hello-bsp"
    local sha
    sha="$(printf '%s' "${content}" | sha256sum | awk '{print $1}')"
    JR_CURL_FAKE_BODY="${content}"
    download_artifact \
        "${JR_WORKDIR}/cache/jp-6.2.1/Jetson_Linux.tbz2" \
        "https://example.invalid/bsp.tbz2" \
        "${sha}"
    [ -f "${JR_WORKDIR}/cache/jp-6.2.1/Jetson_Linux.tbz2" ]
    assert_equal \
        "$(cat "${JR_WORKDIR}/cache/jp-6.2.1/Jetson_Linux.tbz2")" \
        "${content}"
}

@test "download_artifact fails when sha256 mismatches" {
    JR_CURL_FAKE_BODY="wrong content"
    run download_artifact \
        "${JR_WORKDIR}/cache/jp-6.2.1/Jetson_Linux.tbz2" \
        "https://example.invalid/bsp.tbz2" \
        "0000000000000000000000000000000000000000000000000000000000000000"
    assert_failure 2
    [[ "${output}" == *checksum\ mismatch* ]]
    [ ! -f "${JR_WORKDIR}/cache/jp-6.2.1/Jetson_Linux.tbz2" ]
}

@test "download_artifact skips download when existing file matches sha256" {
    local content="hello-bsp"
    local sha
    sha="$(printf '%s' "${content}" | sha256sum | awk '{print $1}')"
    mkdir -p "${JR_WORKDIR}/cache/jp-6.2.1"
    printf '%s' "${content}" >"${JR_WORKDIR}/cache/jp-6.2.1/Jetson_Linux.tbz2"

    : >"${JR_STUB_LOG}"
    download_artifact \
        "${JR_WORKDIR}/cache/jp-6.2.1/Jetson_Linux.tbz2" \
        "https://example.invalid/bsp.tbz2" \
        "${sha}"
    jr_read_stub_log
    [[ "${output}" != *curl* ]]
}
