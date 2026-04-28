#!/usr/bin/env bats

load ../helpers/load

@test "every jetpack config defines all required keys with non-placeholder values" {
    local required=(
        JR_JETPACK_VERSION JR_L4T_VERSION
        JR_BSP_URL JR_BSP_FILENAME
        JR_ROOTFS_URL JR_ROOTFS_FILENAME
        JR_FLASH_IMAGE
    )
    for f in "${JR_REPO_ROOT}/jetpacks"/*.conf; do
        unset "${required[@]}"
        # shellcheck source=/dev/null
        source "${f}"
        for key in "${required[@]}"; do
            [ -n "${!key:-}" ] || fail "${f}: ${key} is unset or empty"
            [[ "${!key}" != *REPLACE_AT_IMPLEMENTATION_TIME* ]] || \
                fail "${f}: ${key} still contains the placeholder marker"
        done
    done
}

@test "BSP and rootfs URLs are HTTPS" {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/jetpacks/6.2.1.conf"
    [[ "${JR_BSP_URL}" == https://* ]]
    [[ "${JR_ROOTFS_URL}" == https://* ]]
}
