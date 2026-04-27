#!/usr/bin/env bash
set -euo pipefail

if [[ "${JETSON_RESTORE_E2E:-0}" != "1" ]]; then
    echo "set JETSON_RESTORE_E2E=1 to run hardware tests" >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${REPO_ROOT}"

echo "=== flashing Orin Nano dev kit ==="
./bin/jetson-restore --target orin-nano-devkit

echo "=== waiting 60s for first boot ==="
sleep 60

# The device should be reachable on the RNDIS link at 192.168.55.1/24.
# After flashing, the device's address depends on its config; the simplest
# check is to ssh into it. The user must have set up an SSH key during flash
# (the sample rootfs has nvidia/nvidia user/pass by default; consider hardening).
DEVICE_ADDR="${E2E_DEVICE_ADDR:-192.168.55.1}"
DEVICE_USER="${E2E_DEVICE_USER:-nvidia}"

echo "=== verifying L4T release on device (${DEVICE_USER}@${DEVICE_ADDR}) ==="
sshpass -p "${E2E_DEVICE_PASS:-nvidia}" ssh -o StrictHostKeyChecking=accept-new \
    "${DEVICE_USER}@${DEVICE_ADDR}" cat /etc/nv_tegra_release | tee /tmp/jr-e2e-orin-nano.log

grep -q "R36 (release), REVISION: 4.4" /tmp/jr-e2e-orin-nano.log || {
    echo "FAIL: nv_tegra_release does not match R36.4.4"
    exit 1
}

echo "PASS: Orin Nano dev kit flashed to JetPack 6.2.1 / L4T R36.4.4"
