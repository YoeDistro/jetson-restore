#!/usr/bin/env bash
# Run NVIDIA's official Jetson Linux flash container against the BSP tree.
#
# We don't ship our own image: NVIDIA already publishes one with every
# dependency the flash tools need (qemu-user-static, binfmt-support,
# nfs-kernel-server, libxml2-utils, cpp, openssh-client, udev, ...).
# See https://catalog.ngc.nvidia.com/orgs/nvidia/containers/jetson-linux-flash-x86
#
# share/entrypoint.sh is mounted in at runtime to drive apply_binaries.sh
# and dispatch to flash.sh / l4t_initrd_flash.sh.
set -euo pipefail

# Pull the NVIDIA flash image if it isn't already cached locally. NGC public
# images don't require auth, but the registry can be flaky; surface the failure
# clearly rather than silently falling back.
_ensure_image() {
    local runtime="$1" image="$2"
    if "${runtime}" image exists "${image}" 2>/dev/null; then
        return 0
    fi
    log_info "pulling ${image}"
    if ! "${runtime}" pull "${image}"; then
        log_die "failed to pull ${image} from NVIDIA NGC; check network and try again"
    fi
}

do_flash() {
    local runtime
    runtime="$(detect_runtime)"
    local image="${JR_FLASH_IMAGE}"

    _ensure_image "${runtime}" "${image}"

    log_info "running ${image}"
    # Four non-obvious mount choices:
    #
    #  * /run/udev so l4t_initrd_flash.sh's container-awareness check
    #    (`udevadm info` on each VID 0955 device) sees real entries.
    #
    #  * /run/rpcbind.sock from the host. The container starts its own
    #    rpcbind (which can't bind port 111 because --net host gives the
    #    host's rpcbind that port already), then starts rpc.mountd which
    #    registers via this Unix socket. Without the bind mount, mountd
    #    registers with the container's zombie rpcbind and the host's
    #    rpcbind never learns about it — `showmount -e localhost` then
    #    returns "Program not registered." With it, mountd registers
    #    with the real rpcbind and showmount works.
    #
    #  * Linux_for_Tegra bind-mounted to the SAME path inside the
    #    container as on the host. NVIDIA's nfs_check prefix-matches
    #    the BSP path against the active NFS exports list, and the
    #    container's nfsd (started via --net host) controls the host
    #    kernel's nfsd — so the path has to be identical on both sides.
    #
    #  * Our entrypoint script mounted in read-only at a fixed location;
    #    we override NVIDIA's default CMD with --entrypoint to drive it.
    local lt="${JR_WORKDIR}/Linux_for_Tegra"
    "${runtime}" run --rm \
        --privileged \
        --net host \
        -v /dev/bus/usb:/dev/bus/usb \
        -v /run/udev:/run/udev:ro \
        -v /run/rpcbind.sock:/run/rpcbind.sock \
        -v "${lt}:${lt}" \
        -v "${JR_REPO_ROOT}/share/entrypoint.sh:/jr-entrypoint.sh:ro" \
        -e "JR_LINUX_FOR_TEGRA=${lt}" \
        -e USER=root \
        --entrypoint /jr-entrypoint.sh \
        "${image}" \
        "${JR_BOARD_ID}" "${JR_STORAGE}"
}
