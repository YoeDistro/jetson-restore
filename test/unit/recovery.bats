#!/usr/bin/env bats

load ../helpers/load

setup() {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/util.sh"
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/recovery.sh"
    export JR_LSUSB_OUTPUT
}

@test "find_jetson_devices returns empty when no 0955 present" {
    jr_use_stub lsusb
    JR_LSUSB_OUTPUT="" run find_jetson_devices
    assert_success
    assert_output ""
}

@test "find_jetson_devices returns one bus:dev for one matching device" {
    jr_use_stub lsusb
    JR_LSUSB_OUTPUT="Bus 003 Device 042: ID 0955:7e19 NVIDIA Corp. APX" \
        run find_jetson_devices
    assert_success
    assert_output "003:042 7e19"
}

@test "find_jetson_devices returns multiple lines for multiple devices" {
    jr_use_stub lsusb
    JR_LSUSB_OUTPUT="\
Bus 003 Device 042: ID 0955:7e19 NVIDIA Corp. APX
Bus 004 Device 015: ID 0955:7023 NVIDIA Corp. APX" \
        run find_jetson_devices
    assert_success
    assert_line --index 0 "003:042 7e19"
    assert_line --index 1 "004:015 7023"
}

@test "wait_for_recovery returns 0 when device appears within timeout" {
    jr_use_stub lsusb
    JR_LSUSB_OUTPUT="Bus 003 Device 042: ID 0955:7e19 NVIDIA Corp. APX"
    run wait_for_recovery "7e19" 2
    assert_success
}

@test "wait_for_recovery returns 1 when device never appears" {
    jr_use_stub lsusb
    JR_LSUSB_OUTPUT=""
    run wait_for_recovery "7e19" 1
    assert_failure 1
}
