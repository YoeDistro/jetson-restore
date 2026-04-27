#!/usr/bin/env bash
# Download BSP/rootfs tarballs from developer.nvidia.com.
# Trust root: HTTPS to developer.nvidia.com. No checksum pinning.
set -euo pipefail

download_artifact() {
    local dest="$1" url="$2"
    local dest_dir
    dest_dir="$(dirname "${dest}")"
    mkdir -p "${dest_dir}"

    if [[ -f "${dest}" ]]; then
        log_info "cached: ${dest}"
        return 0
    fi

    local partial="${dest}.partial"
    log_info "downloading $(basename "${dest}") ..."
    curl --fail --location --show-error \
        --connect-timeout 30 --retry 3 \
        -o "${partial}" "${url}"
    mv -f "${partial}" "${dest}"
}

# Higher-level: ensure both BSP and rootfs are cached and extracted.
ensure_l4t_extracted() {
    local workdir="$1"
    local cache="${workdir}/cache/jp-${JR_JETPACK_VERSION}"
    local bsp="${cache}/${JR_BSP_FILENAME}"
    local rootfs="${cache}/${JR_ROOTFS_FILENAME}"

    download_artifact "${bsp}" "${JR_BSP_URL}"
    download_artifact "${rootfs}" "${JR_ROOTFS_URL}"

    local lt="${workdir}/Linux_for_Tegra"
    # If the prior container run died mid-apply_binaries.sh, the rootfs is
    # in a partial state that can't be recovered (e.g. /dev nodes already
    # exist, breaking the next mknod). Wipe and re-extract.
    if [[ -f "${lt}/.jr-rootfs-dirty" ]]; then
        log_info "previous run left rootfs in a partial state; wiping and re-extracting"
        run_sudo rm -rf "${lt}/rootfs"
        rm -f "${lt}/.jr-extracted-${JR_JETPACK_VERSION}" "${lt}/.jr-rootfs-dirty"
    fi
    if [[ ! -f "${lt}/.jr-extracted-${JR_JETPACK_VERSION}" ]]; then
        log_info "extracting BSP into ${lt}"
        mkdir -p "${workdir}"
        tar -xpf "${bsp}" -C "${workdir}"
        # The sample rootfs has setuid binaries, device nodes, and root-owned
        # files. NVIDIA's apply_binaries.sh validates ownership and rejects an
        # unprivileged extraction with "rootfs has to be extracted with 'sudo'".
        log_info "extracting rootfs into ${lt}/rootfs/ (requires sudo)"
        mkdir -p "${lt}/rootfs"
        run_sudo tar -xpf "${rootfs}" -C "${lt}/rootfs"
        : >"${lt}/.jr-extracted-${JR_JETPACK_VERSION}"
    else
        log_info "Linux_for_Tegra already extracted for ${JR_JETPACK_VERSION}"
    fi
}
