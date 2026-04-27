#!/usr/bin/env bats

load ../helpers/load

@test "udev rule contains @JR_GROUP@ placeholder" {
    grep -q '@JR_GROUP@' "${JR_REPO_ROOT}/share/70-jetson-restore.rules"
}

@test "NM keyfile contains @JR_RNDIS_MAC@ placeholder" {
    grep -q '@JR_RNDIS_MAC@' "${JR_REPO_ROOT}/share/jetson-restore.nmconnection.tmpl"
}

@test "exports template contains @JR_EXPORT_PATH@ placeholder" {
    grep -q '@JR_EXPORT_PATH@' "${JR_REPO_ROOT}/share/jetson-restore.exports.tmpl"
}

@test "exports template restricts to RNDIS subnet 192.168.55.0/24" {
    grep -q '192.168.55.0/24' "${JR_REPO_ROOT}/share/jetson-restore.exports.tmpl"
}
