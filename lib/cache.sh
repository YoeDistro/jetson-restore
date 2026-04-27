#!/usr/bin/env bash
# Download and verify BSP/rootfs tarballs.
set -euo pipefail

_sha256_of() { sha256sum "$1" | awk '{print $1}'; }

download_artifact() {
    local dest="$1" url="$2" expected_sha="$3"
    local dest_dir
    dest_dir="$(dirname "${dest}")"
    mkdir -p "${dest_dir}"

    if [[ -f "${dest}" ]] && [[ "$(_sha256_of "${dest}")" == "${expected_sha}" ]]; then
        log_info "cached: ${dest}"
        return 0
    fi

    local partial="${dest}.partial"
    log_info "downloading $(basename "${dest}") ..."
    curl --fail --location --show-error \
        --connect-timeout 30 --retry 3 \
        -o "${partial}" "${url}"

    local actual_sha
    actual_sha="$(_sha256_of "${partial}")"
    if [[ "${actual_sha}" != "${expected_sha}" ]]; then
        rm -f "${partial}"
        log_die "checksum mismatch for ${url}: expected ${expected_sha}, got ${actual_sha}"
    fi
    mv -f "${partial}" "${dest}"
}

# Higher-level: ensure both BSP and rootfs are cached and extracted.
ensure_l4t_extracted() {
    local workdir="$1"
    local cache="${workdir}/cache/jp-${JR_JETPACK_VERSION}"
    local bsp="${cache}/${JR_BSP_FILENAME}"
    local rootfs="${cache}/${JR_ROOTFS_FILENAME}"

    download_artifact "${bsp}" "${JR_BSP_URL}" "${JR_BSP_SHA256}"
    download_artifact "${rootfs}" "${JR_ROOTFS_URL}" "${JR_ROOTFS_SHA256}"

    local lt="${workdir}/Linux_for_Tegra"
    if [[ ! -f "${lt}/.jr-extracted-${JR_JETPACK_VERSION}" ]]; then
        log_info "extracting BSP into ${lt}"
        mkdir -p "${workdir}"
        tar -xpf "${bsp}" -C "${workdir}"
        log_info "extracting rootfs into ${lt}/rootfs/"
        mkdir -p "${lt}/rootfs"
        tar -xpf "${rootfs}" -C "${lt}/rootfs"
        : >"${lt}/.jr-extracted-${JR_JETPACK_VERSION}"
    else
        log_info "Linux_for_Tegra already extracted for ${JR_JETPACK_VERSION}"
    fi
}
