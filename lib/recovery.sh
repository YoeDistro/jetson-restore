#!/usr/bin/env bash
# Detect Jetson devices in recovery mode (USB VID 0955).
set -euo pipefail

# Print "BBB:DDD PRODID" for each VID 0955 device on the USB bus.
find_jetson_devices() {
    local line bus dev product
    while IFS= read -r line; do
        # Format: "Bus 003 Device 042: ID 0955:7e19 NVIDIA Corp. APX"
        if [[ "${line}" =~ ^Bus\ ([0-9]+)\ Device\ ([0-9]+):\ ID\ 0955:([0-9a-fA-F]{4}) ]]; then
            bus="${BASH_REMATCH[1]}"
            dev="${BASH_REMATCH[2]}"
            product="${BASH_REMATCH[3]}"
            printf '%s:%s %s\n' "${bus}" "${dev}" "${product}"
        fi
    done < <(lsusb)
}

# Wait up to TIMEOUT_S seconds for a device with the given USB product ID.
wait_for_recovery() {
    local product_id="$1" timeout_s="$2"
    local elapsed=0
    # Export so the lsusb stub can read JR_LSUSB_OUTPUT from the environment.
    export JR_LSUSB_OUTPUT
    while ((elapsed < timeout_s)); do
        if find_jetson_devices | awk '{print $2}' | grep -qx "${product_id}"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}
