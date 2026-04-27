#!/usr/bin/env bash
# Loaders for targets/*.conf and jetpacks/*.conf.
set -euo pipefail

# Names must be a single path component, no slashes or dots.
_validate_name() {
    local name="$1"
    if [[ ! "${name}" =~ ^[A-Za-z0-9._-]+$ ]] || [[ "${name}" == *..* ]]; then
        log_die "invalid target name: ${name}"
    fi
}

load_target() {
    local repo="$1" name="$2"
    _validate_name "${name}"
    local f="${repo}/targets/${name}.conf"
    if [[ ! -f "${f}" ]]; then
        log_die "unknown target: ${name} (no ${f})"
    fi
    # shellcheck source=/dev/null
    source "${f}"
}

load_jetpack() {
    local repo="$1" version="$2"
    _validate_name "${version}"
    local f="${repo}/jetpacks/${version}.conf"
    if [[ ! -f "${f}" ]]; then
        log_die "unknown jetpack: ${version} (no ${f})"
    fi
    # shellcheck source=/dev/null
    source "${f}"
}

list_targets() {
    local repo="$1"
    local f
    for f in "${repo}/targets"/*.conf; do
        basename "${f}" .conf
    done
}
