#!/usr/bin/env bats

load ../helpers/load

@test "every target file defines all required keys" {
    local required=(
        JR_TARGET_NAME JR_BOARD_ID JR_USB_PRODUCT_ID
        JR_DEFAULT_JETPACK JR_DEFAULT_STORAGE JR_VALID_STORAGE
        JR_RECOVERY_INSTRUCTIONS
    )
    for f in "${JR_REPO_ROOT}/targets"/*.conf; do
        unset "${required[@]}"
        # shellcheck source=/dev/null
        source "${f}"
        for key in "${required[@]}"; do
            [ -n "${!key:-}" ] || \
                fail "${f}: ${key} is unset or empty"
        done
        # Default must be in the valid set.
        grep -qw "${JR_DEFAULT_STORAGE}" <<<"${JR_VALID_STORAGE}" || \
            fail "${f}: JR_DEFAULT_STORAGE='${JR_DEFAULT_STORAGE}' not in JR_VALID_STORAGE='${JR_VALID_STORAGE}'"
    done
}

@test "Orin Nano product ID is 7e19" {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/targets/orin-nano-devkit.conf"
    assert_equal "${JR_USB_PRODUCT_ID}" "7e19"
}

@test "AGX Orin product ID is 7023" {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/targets/agx-orin-devkit.conf"
    assert_equal "${JR_USB_PRODUCT_ID}" "7023"
}
