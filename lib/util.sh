#!/usr/bin/env bash
# Shared utilities. Source this first.
set -euo pipefail

# Defaults; the entrypoint may override.
: "${JR_NO_SUDO:=0}"
: "${JR_DRY_RUN:=0}"
: "${JR_SUDO_QUEUE_FILE:=}"

log_info() { printf '[INFO] %s\n' "$*" >&2; }
log_warn() { printf '[WARN] %s\n' "$*" >&2; }
log_err() { printf '[ERROR] %s\n' "$*" >&2; }

log_die() {
    log_err "$*"
    exit 2
}

# run_cmd: respects --dry-run; does not elevate.
run_cmd() {
    if [[ "${JR_DRY_RUN}" == "1" ]]; then
        printf '[DRY-RUN] %s\n' "$*" >&2
        return 0
    fi
    "$@"
}

# run_sudo: respects --no-sudo (queues to a file) and --dry-run (prints).
run_sudo() {
    if [[ "${JR_DRY_RUN}" == "1" ]]; then
        printf '[DRY-RUN] sudo %s\n' "$*" >&2
        return 0
    fi
    if [[ "${JR_NO_SUDO}" == "1" ]]; then
        if [[ -z "${JR_SUDO_QUEUE_FILE}" ]]; then
            log_die "JR_NO_SUDO=1 but JR_SUDO_QUEUE_FILE is unset"
        fi
        # Quote each arg for safe re-execution by the user later.
        printf 'sudo' >>"${JR_SUDO_QUEUE_FILE}"
        for arg in "$@"; do
            printf ' %q' "${arg}" >>"${JR_SUDO_QUEUE_FILE}"
        done
        printf '\n' >>"${JR_SUDO_QUEUE_FILE}"
        return 0
    fi
    sudo "$@"
}
