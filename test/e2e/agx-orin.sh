#!/usr/bin/env bash
set -euo pipefail

if [[ "${JETSON_RESTORE_E2E:-0}" != "1" ]]; then
    echo "set JETSON_RESTORE_E2E=1 to run hardware tests" >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${REPO_ROOT}"

echo "=== flashing AGX Orin dev kit ==="
./bin/jetson-restore --target agx-orin-devkit

echo "=== waiting 90s for first boot (AGX is slower) ==="
sleep 90

DEVICE_ADDR="${E2E_DEVICE_ADDR:-192.168.55.1}"
DEVICE_USER="${E2E_DEVICE_USER:-nvidia}"

echo "=== verifying L4T release on device ==="
sshpass -p "${E2E_DEVICE_PASS:-nvidia}" ssh -o StrictHostKeyChecking=accept-new \
    "${DEVICE_USER}@${DEVICE_ADDR}" cat /etc/nv_tegra_release | tee /tmp/jr-e2e-agx-orin.log

grep -q "R36 (release), REVISION: 4.4" /tmp/jr-e2e-agx-orin.log || {
    echo "FAIL: nv_tegra_release does not match R36.4.4"
    exit 1
}

echo "PASS: AGX Orin dev kit flashed to JetPack 6.2.1 / L4T R36.4.4"
