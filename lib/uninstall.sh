#!/usr/bin/env bash
# Reverse everything preflight installed.
set -euo pipefail

do_uninstall() {
    log_info "uninstalling jetson-restore host config"
    remove_udev_rule
    remove_nm_keyfile
    log_info "done; cached BSP under ./work/cache/ is intact"
}
