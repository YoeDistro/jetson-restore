# Sourced at the top of every .bats file via `load helpers/load`.
load "${BATS_TEST_DIRNAME}/../helpers/bats-support/load"
load "${BATS_TEST_DIRNAME}/../helpers/bats-assert/load"

# Repo root, available to tests.
JR_REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
export JR_REPO_ROOT

# Per-test temp dir; auto-cleaned by bats.
JR_TMPDIR="${BATS_TEST_TMPDIR}"
export JR_TMPDIR

# Activate a stub by symlinking it into a per-test bin/ that's first on PATH.
jr_use_stub() {
    local stub_name="$1"
    local stubs_active="${JR_TMPDIR}/stubs-active"
    mkdir -p "${stubs_active}"
    ln -sf "${JR_REPO_ROOT}/test/helpers/stubs/${stub_name}" \
        "${stubs_active}/${stub_name}"
    PATH="${stubs_active}:${PATH}"
    export PATH
    # Stubs record argv to this file when called.
    JR_STUB_LOG="${JR_TMPDIR}/stub.log"
    : > "${JR_STUB_LOG}"
    export JR_STUB_LOG
}

# Read the stub log into BATS' `output` variable for assertions.
jr_read_stub_log() {
    output="$(cat "${JR_STUB_LOG}")"
}
