#!/usr/bin/env bats

load ../helpers/load

@test "udev rule contains @JR_GROUP@ placeholder" {
    grep -q '@JR_GROUP@' "${JR_REPO_ROOT}/share/70-jetson-restore.rules"
}

@test "NM keyfile contains @JR_RNDIS_MAC@ placeholder" {
    grep -q '@JR_RNDIS_MAC@' "${JR_REPO_ROOT}/share/jetson-restore.nmconnection.tmpl"
}
