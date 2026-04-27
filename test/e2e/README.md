# End-to-end tests

These tests run a full flash against a real device and verify the result.
They are NOT run in CI — they need hardware and take ~30 minutes each.

To run:

    JETSON_RESTORE_E2E=1 ./test/e2e/orin-nano.sh
    JETSON_RESTORE_E2E=1 ./test/e2e/agx-orin.sh

Expected output: PASS, with the captured `cat /etc/nv_tegra_release` from the
device matching the expected JetPack version.

Run before tagging a release. Paste the log into the GitHub Release notes.
