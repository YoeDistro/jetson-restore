# jetson-restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a maintained, distributable, one-command tool that restores stock NVIDIA L4T Ubuntu onto Jetson Orin Nano and AGX Orin dev kits from any modern Linux host (primary target: Arch Linux).

**Architecture:** Two-layer design. A bash wrapper on the host handles preflight (udev, NetworkManager, NFS export, USB checks) and orchestration; a pinned Ubuntu 22.04 container carries NVIDIA's BSP toolchain and runs `l4t_initrd_flash.sh`. Shared state lives in a bind-mounted `./work/` directory the container and the host NFS server both see.

**Tech Stack:** bash 5+, bats-core (testing), shellcheck (lint), shfmt (format), podman/docker (container runtime), Ubuntu 22.04 + NVIDIA L4T R36.4.4 BSP (in-container), GitHub Actions (CI), GitHub Container Registry (distribution).

**Spec:** `docs/superpowers/specs/2026-04-27-jetson-restore-design.md`

---

## Conventions used in every shell file

Every `bin/` and `lib/` file in this project starts with:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

- `set -e`: exit on first error
- `set -u`: error on unset variable
- `set -o pipefail`: a pipeline fails if any stage fails

`lib/` files are sourced, not executed; the shebang is informational and not exec'd, but the strict-mode line still applies because the wrapper sets it before sourcing.

Strings are always double-quoted unless globbing is intended. All variable expansions use `${var}`, not `$var`. All command substitutions use `$(...)`, not backticks.

Logging goes through `lib/util.sh::log_info`, `log_warn`, `log_err`, `log_die`. Plain `echo` is reserved for command output.

Sudo is only invoked through `lib/util.sh::run_sudo`, which respects `--no-sudo` and `--dry-run`.

---

## File structure

```
jetson-restore/
├── bin/
│   └── jetson-restore               # CLI entrypoint, arg parsing, subcommand dispatch
├── lib/
│   ├── util.sh                      # logging, run_sudo, run_cmd helpers; sourced first
│   ├── config.sh                    # load targets/*.conf and jetpacks/*.conf
│   ├── runtime.sh                   # detect podman/docker, build run argv
│   ├── recovery.sh                  # detect VID 0955, identify model
│   ├── udev.sh                      # install/remove the udev rule
│   ├── netmgr.sh                    # install/remove the NM keyfile
│   ├── nfs.sh                       # manage exports.d snippet, nfs-server state
│   ├── cache.sh                     # download + verify BSP/rootfs tarballs
│   ├── preflight.sh                 # orchestrate the 12 preflight checks
│   ├── flash.sh                     # assemble container invocation
│   └── uninstall.sh                 # remove udev, NM, exports.d
├── targets/
│   ├── orin-nano-devkit.conf
│   └── agx-orin-devkit.conf
├── jetpacks/
│   └── 6.2.1.conf
├── container/
│   ├── Containerfile
│   └── entrypoint.sh
├── share/
│   ├── 70-jetson-restore.rules
│   ├── jetson-restore.nmconnection.tmpl
│   └── jetson-restore.exports.tmpl
├── test/
│   ├── helpers/
│   │   ├── load.bash               # bats helper to source bats-assert/bats-support
│   │   └── stubs/                  # PATH-injected fakes (sudo, lsusb, systemctl, …)
│   ├── unit/                        # bats tests, no hardware
│   └── e2e/                         # gated on JETSON_RESTORE_E2E=1
├── .github/
│   └── workflows/
│       ├── ci.yml                   # lint + bats + container build per PR
│       └── release.yml              # tag → ghcr.io push
├── docs/
│   ├── superpowers/                 # specs and plans (this file lives here)
│   ├── README.md                    # quick start
│   ├── ARCHITECTURE.md              # for contributors
│   └── TROUBLESHOOTING.md           # for users hitting flash failures
├── .editorconfig
├── .shellcheckrc
├── .shfmt
├── Makefile                         # `make lint test container`
└── LICENSE
```

---

## Phase 1: Scaffolding

### Task 1: Initialize project skeleton, lint config, license

**Files:**
- Create: `LICENSE`
- Create: `.editorconfig`
- Create: `.shellcheckrc`
- Create: `.gitignore`
- Create: `Makefile`
- Create: `docs/README.md` (placeholder; full README later)

- [ ] **Step 1: Create LICENSE (Apache-2.0)**

```bash
curl -sSL https://www.apache.org/licenses/LICENSE-2.0.txt -o LICENSE
```

If the download fails, paste the standard Apache-2.0 license text manually. The license choice matches Yoe Distro and most NVIDIA-adjacent tooling.

- [ ] **Step 2: Create `.editorconfig`**

```ini
root = true

[*]
indent_style = space
indent_size = 4
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true

[*.md]
trim_trailing_whitespace = false

[Makefile]
indent_style = tab
```

- [ ] **Step 3: Create `.shellcheckrc`**

```
# Ignore SC1091: shellcheck can't follow runtime sourced files.
# Our lib/*.sh sourcing pattern is intentional.
disable=SC1091
# Treat warnings as errors in CI.
severity=warning
```

- [ ] **Step 4: Create `.gitignore`**

```
work/
*.swp
.DS_Store
result/
```

- [ ] **Step 5: Create initial `Makefile`**

```makefile
.PHONY: lint test container clean help

SHELL := bash
.SHELLFLAGS := -euo pipefail -c

SHELL_FILES := $(shell find bin lib container share -type f \
                  \( -name '*.sh' -o -name 'jetson-restore' -o -name 'entrypoint.sh' \) 2>/dev/null)

help:
	@echo "Targets:"
	@echo "  lint       run shellcheck + shfmt"
	@echo "  test       run bats unit tests"
	@echo "  container  build the flash container locally"
	@echo "  clean      remove ./work/"

lint:
	shellcheck $(SHELL_FILES)
	shfmt -d -i 4 -ci $(SHELL_FILES)

test:
	bats -r test/unit

container:
	podman build -t jetson-restore:dev -f container/Containerfile container/

clean:
	rm -rf work/
```

- [ ] **Step 6: Create placeholder `docs/README.md`**

```markdown
# jetson-restore

Restore stock NVIDIA L4T Ubuntu onto Jetson Orin dev kits from any modern Linux host.

See [docs/superpowers/specs/2026-04-27-jetson-restore-design.md](superpowers/specs/2026-04-27-jetson-restore-design.md) for the design.

Status: under construction.
```

- [ ] **Step 7: Commit**

```bash
git add LICENSE .editorconfig .shellcheckrc .gitignore Makefile docs/README.md
git commit -m "chore: initialize project skeleton"
```

---

### Task 2: Bats helpers and stub framework

**Files:**
- Create: `test/helpers/load.bash`
- Create: `test/helpers/stubs/README.md`
- Create: `test/unit/smoke.bats`

The "stub" pattern: tests prepend `test/helpers/stubs-active/` to `PATH`, drop a fake binary in there (e.g., `sudo`, `lsusb`) that records its argv to a file, then assert against the recorded argv. This lets us test preflight code without root and without hardware.

- [ ] **Step 1: Vendor bats-assert and bats-support as git submodules**

```bash
git submodule add https://github.com/bats-core/bats-support test/helpers/bats-support
git submodule add https://github.com/bats-core/bats-assert  test/helpers/bats-assert
```

If submodules are problematic in CI, add a `make bootstrap-tests` target later that clones them. Submodules are simpler day-1.

- [ ] **Step 2: Create `test/helpers/load.bash`**

```bash
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
```

- [ ] **Step 3: Create `test/helpers/stubs/README.md`**

```markdown
# Stubs

Each file in this directory is a fake of a system command. When a test calls
`jr_use_stub <name>`, the stub is symlinked into a per-test bin/ that's prepended
to PATH. The stub logs its argv to `${JR_STUB_LOG}` and exits 0.

Add a new stub by dropping a script here, marking it executable, and naming it
after the command it shadows.
```

- [ ] **Step 4: Create a smoke bats test**

```bash
mkdir -p test/unit
cat >test/unit/smoke.bats <<'EOF'
#!/usr/bin/env bats

load ../helpers/load

@test "bats helpers load and JR_REPO_ROOT is set" {
    [ -n "${JR_REPO_ROOT}" ]
    [ -d "${JR_REPO_ROOT}" ]
    [ -f "${JR_REPO_ROOT}/Makefile" ]
}
EOF
```

- [ ] **Step 5: Run the smoke test**

```bash
bats test/unit/smoke.bats
```

Expected: `1 test, 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add .gitmodules test/
git commit -m "test: add bats helpers and smoke test"
```

---

### Task 3: CI workflow — lint and unit tests

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create the workflow**

```yaml
name: ci

on:
  push:
    branches: [main]
  pull_request:

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install shellcheck and shfmt
        run: |
          sudo apt-get update
          sudo apt-get install -y shellcheck
          curl -sSL https://github.com/mvdan/sh/releases/download/v3.7.0/shfmt_v3.7.0_linux_amd64 \
            -o /usr/local/bin/shfmt
          sudo chmod +x /usr/local/bin/shfmt
      - name: Lint
        run: make lint

  test-ubuntu:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - name: Install bats
        run: sudo apt-get update && sudo apt-get install -y bats
      - name: Run unit tests
        run: make test

  test-arch:
    runs-on: ubuntu-latest
    container: archlinux:latest
    steps:
      - name: Install deps
        run: pacman -Sy --noconfirm git bash bats make
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - name: Run unit tests
        run: make test
```

- [ ] **Step 2: Verify locally that `make lint` passes on what exists so far**

```bash
make lint
```

Expected: exit 0 (no shell files yet besides Makefile config; shellcheck and shfmt should both pass).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add lint and bats jobs for ubuntu and arch"
```

---

## Phase 2: Configuration files (data, no logic yet)

### Task 4: Define target configs (orin-nano-devkit, agx-orin-devkit)

**Files:**
- Create: `targets/orin-nano-devkit.conf`
- Create: `targets/agx-orin-devkit.conf`
- Create: `test/unit/targets.bats`

Targets are plain `KEY=value` shell files. Keys:
- `JR_TARGET_NAME` — human label
- `JR_BOARD_ID` — what `l4t_initrd_flash.sh` calls `--external-device` and the BOARD env it uses (e.g., `jetson-orin-nano-devkit`)
- `JR_USB_PRODUCT_ID` — recovery-mode USB product (e.g., `7e19`)
- `JR_DEFAULT_JETPACK` — JetPack version this target was tested with
- `JR_RECOVERY_INSTRUCTIONS` — multi-line string describing how to put the board into recovery mode

- [ ] **Step 1: Write `targets/orin-nano-devkit.conf`**

```bash
# shellcheck shell=bash
# Orin Nano dev kit (Super, NVMe-only).
JR_TARGET_NAME="Orin Nano dev kit"
JR_BOARD_ID="jetson-orin-nano-devkit"
JR_USB_PRODUCT_ID="7e19"
JR_DEFAULT_JETPACK="6.2.1"
JR_DEFAULT_STORAGE="nvme"
JR_RECOVERY_INSTRUCTIONS="\
Place the Orin Nano dev kit in recovery mode:
  1. Power off the board.
  2. Connect a jumper between pins 9 and 10 (FC REC and GND) on the carrier
     board's J14 button header.
  3. Connect USB-C from the dev kit to this host.
  4. Power on the board.
  5. Verify with: lsusb | grep '0955:7e19'"
```

- [ ] **Step 2: Write `targets/agx-orin-devkit.conf`**

```bash
# shellcheck shell=bash
# AGX Orin dev kit.
JR_TARGET_NAME="AGX Orin dev kit"
JR_BOARD_ID="jetson-agx-orin-devkit"
JR_USB_PRODUCT_ID="7023"
JR_DEFAULT_JETPACK="6.2.1"
JR_DEFAULT_STORAGE="nvme"
JR_RECOVERY_INSTRUCTIONS="\
Place the AGX Orin dev kit in recovery mode:
  1. Power off the board.
  2. Connect USB-C from the front of the dev kit to this host.
  3. Press and hold the FORCE RECOVERY button.
  4. While holding, press and release the POWER button.
  5. Release FORCE RECOVERY after ~2 seconds.
  6. Verify with: lsusb | grep '0955:7023'"
```

- [ ] **Step 3: Write a bats test that loads each target file and asserts the required keys are set**

```bash
cat >test/unit/targets.bats <<'EOF'
#!/usr/bin/env bats

load ../helpers/load

@test "every target file defines all required keys" {
    local required=(
        JR_TARGET_NAME JR_BOARD_ID JR_USB_PRODUCT_ID
        JR_DEFAULT_JETPACK JR_DEFAULT_STORAGE JR_RECOVERY_INSTRUCTIONS
    )
    for f in "${JR_REPO_ROOT}/targets"/*.conf; do
        unset "${required[@]}"
        # shellcheck source=/dev/null
        source "${f}"
        for key in "${required[@]}"; do
            [ -n "${!key:-}" ] || \
                fail "${f}: ${key} is unset or empty"
        done
    done
}

@test "Orin Nano product ID is 7e19" {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/targets/orin-nano-devkit.conf"
    assert_equal "${JR_USB_PRODUCT_ID}" "7e19"
}

@test "AGX Orin product ID is 7023" {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/targets/agx-orin-devkit.conf"
    assert_equal "${JR_USB_PRODUCT_ID}" "7023"
}
EOF
```

- [ ] **Step 4: Run the test**

```bash
bats test/unit/targets.bats
```

Expected: `3 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add targets/ test/unit/targets.bats
git commit -m "feat(targets): add orin-nano-devkit and agx-orin-devkit configs"
```

---

### Task 5: Define JetPack 6.2.1 config

**Files:**
- Create: `jetpacks/6.2.1.conf`
- Create: `test/unit/jetpacks.bats`

JetPack configs hold the BSP and rootfs tarball URLs and SHA-256 checksums. The exact URLs, sizes, and hashes come from the NVIDIA L4T downloads page for R36.4.4. The implementer must look these up at implementation time and paste them in — the URLs change occasionally.

- [ ] **Step 1: Write `jetpacks/6.2.1.conf`**

```bash
# shellcheck shell=bash
# JetPack 6.2.1 / L4T R36.4.4
# Source: https://developer.nvidia.com/embedded/jetson-linux-r3644

JR_JETPACK_VERSION="6.2.1"
JR_L4T_VERSION="R36.4.4"

# Driver package (BSP) tarball.
JR_BSP_URL="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.4/release/Jetson_Linux_R36.4.4_aarch64.tbz2"
JR_BSP_SHA256="REPLACE_AT_IMPLEMENTATION_TIME"
JR_BSP_FILENAME="Jetson_Linux_R36.4.4_aarch64.tbz2"

# Sample root filesystem tarball.
JR_ROOTFS_URL="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.4/release/Tegra_Linux_Sample-Root-Filesystem_R36.4.4_aarch64.tbz2"
JR_ROOTFS_SHA256="REPLACE_AT_IMPLEMENTATION_TIME"
JR_ROOTFS_FILENAME="Tegra_Linux_Sample-Root-Filesystem_R36.4.4_aarch64.tbz2"

# Container image tag this JetPack version pairs with.
JR_CONTAINER_TAG="6.2.1"
```

**Action item for the implementer:** before merging, replace both `REPLACE_AT_IMPLEMENTATION_TIME` placeholders with the real SHA-256 from `sha256sum` against the freshly downloaded tarballs. The presence of the placeholder will cause the bats test below to fail until it's fixed.

- [ ] **Step 2: Write a bats test that asserts placeholders are gone**

```bash
cat >test/unit/jetpacks.bats <<'EOF'
#!/usr/bin/env bats

load ../helpers/load

@test "every jetpack config defines all required keys with non-placeholder values" {
    local required=(
        JR_JETPACK_VERSION JR_L4T_VERSION
        JR_BSP_URL JR_BSP_SHA256 JR_BSP_FILENAME
        JR_ROOTFS_URL JR_ROOTFS_SHA256 JR_ROOTFS_FILENAME
        JR_CONTAINER_TAG
    )
    for f in "${JR_REPO_ROOT}/jetpacks"/*.conf; do
        unset "${required[@]}"
        # shellcheck source=/dev/null
        source "${f}"
        for key in "${required[@]}"; do
            [ -n "${!key:-}" ] || fail "${f}: ${key} is unset or empty"
            [[ "${!key}" != *REPLACE_AT_IMPLEMENTATION_TIME* ]] || \
                fail "${f}: ${key} still contains the placeholder marker"
        done
    done
}

@test "BSP and rootfs URLs are HTTPS" {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/jetpacks/6.2.1.conf"
    [[ "${JR_BSP_URL}" == https://* ]]
    [[ "${JR_ROOTFS_URL}" == https://* ]]
}

@test "SHA-256 fields are 64 lowercase hex chars" {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/jetpacks/6.2.1.conf"
    [[ "${JR_BSP_SHA256}" =~ ^[0-9a-f]{64}$ ]]
    [[ "${JR_ROOTFS_SHA256}" =~ ^[0-9a-f]{64}$ ]]
}
EOF
```

- [ ] **Step 3: Run the test**

```bash
bats test/unit/jetpacks.bats
```

Expected: tests fail until the implementer fills in the real SHA-256s. This is intentional — it's a forced check.

- [ ] **Step 4: Implementer fills in real SHA-256 values**

Download both tarballs from the URLs in the config, run `sha256sum`, paste the values into `jetpacks/6.2.1.conf`. Then re-run the test.

```bash
bats test/unit/jetpacks.bats
```

Expected after fill-in: `3 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add jetpacks/ test/unit/jetpacks.bats
git commit -m "feat(jetpacks): add 6.2.1 config with BSP and rootfs metadata"
```

---

### Task 6: Share templates (udev rule, NM keyfile, exports.d)

**Files:**
- Create: `share/70-jetson-restore.rules`
- Create: `share/jetson-restore.nmconnection.tmpl`
- Create: `share/jetson-restore.exports.tmpl`
- Create: `test/unit/share.bats`

- [ ] **Step 1: Write the udev rule**

```
# /etc/udev/rules.d/70-jetson-restore.rules
# Allow the user's primary group to access NVIDIA Jetson devices in recovery mode.
# Disable USB autosuspend for these devices to prevent mid-flash drops.
SUBSYSTEM=="usb", ATTR{idVendor}=="0955", MODE="0660", GROUP="@JR_GROUP@", TAG+="uaccess"
SUBSYSTEM=="usb", ATTR{idVendor}=="0955", ATTR{power/control}="on"
```

`@JR_GROUP@` is replaced by the runtime with the user's primary group (`id -gn`). Including `TAG+="uaccess"` lets logind grant access to the locally-logged-in user as a fallback.

- [ ] **Step 2: Write the NetworkManager keyfile template**

```
[connection]
id=jetson-restore-rndis
type=ethernet
interface-name=
match-device=mac:@JR_RNDIS_MAC@
autoconnect=false

[ethernet]
mac-address=@JR_RNDIS_MAC@

[ipv4]
method=disabled

[ipv6]
method=disabled
```

`@JR_RNDIS_MAC@` is the well-known L4T recovery RNDIS MAC; the runtime substitutes the value from the JetPack config (or a constant).

- [ ] **Step 3: Write the NFS exports template**

```
@JR_EXPORT_PATH@ 192.168.55.0/24(rw,sync,no_subtree_check,no_root_squash)
```

`@JR_EXPORT_PATH@` is replaced with the absolute path to `${WORKDIR}/Linux_for_Tegra` at runtime.

- [ ] **Step 4: Write a bats test that all templates exist and contain the placeholders the runtime substitutes**

```bash
cat >test/unit/share.bats <<'EOF'
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
EOF
```

- [ ] **Step 5: Run the test**

```bash
bats test/unit/share.bats
```

Expected: `4 tests, 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add share/ test/unit/share.bats
git commit -m "feat(share): add udev rule, NM keyfile, and exports.d templates"
```

---

## Phase 3: Shared utilities

### Task 7: lib/util.sh — logging, run_sudo, run_cmd

**Files:**
- Create: `lib/util.sh`
- Create: `test/helpers/stubs/sudo`
- Create: `test/unit/util.bats`

`lib/util.sh` is the only file that depends on no other lib file. Everything else sources it.

- [ ] **Step 1: Write the failing test**

```bash
cat >test/unit/util.bats <<'EOF'
#!/usr/bin/env bats

load ../helpers/load

setup() {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/util.sh"
    JR_NO_SUDO=0
    JR_DRY_RUN=0
}

@test "log_info writes to stderr with INFO prefix" {
    run --separate-stderr log_info "hello"
    assert_equal "${stderr}" "[INFO] hello"
}

@test "log_die writes ERROR to stderr and exits 2" {
    run log_die "boom"
    assert_failure 2
    [[ "${output}" == *ERROR*boom* ]]
}

@test "run_sudo invokes sudo with given argv when JR_NO_SUDO=0" {
    jr_use_stub sudo
    JR_NO_SUDO=0 run_sudo systemctl start nfs-server
    jr_read_stub_log
    assert_output "sudo systemctl start nfs-server"
}

@test "run_sudo with JR_NO_SUDO=1 records command and does not invoke sudo" {
    jr_use_stub sudo
    JR_NO_SUDO=1 JR_SUDO_QUEUE_FILE="${JR_TMPDIR}/queue.sh" \
        run_sudo systemctl start nfs-server
    [ ! -s "${JR_STUB_LOG}" ]
    grep -q 'systemctl start nfs-server' "${JR_TMPDIR}/queue.sh"
}

@test "run_cmd with JR_DRY_RUN=1 prints command and does not execute" {
    jr_use_stub sudo
    JR_DRY_RUN=1 run_cmd echo "should-not-run"
    [ ! -s "${JR_STUB_LOG}" ]
}
EOF
```

- [ ] **Step 2: Write the sudo stub**

```bash
mkdir -p test/helpers/stubs
cat >test/helpers/stubs/sudo <<'EOF'
#!/usr/bin/env bash
echo "sudo $*" >>"${JR_STUB_LOG}"
exit 0
EOF
chmod +x test/helpers/stubs/sudo
```

- [ ] **Step 3: Run the test, see it fail**

```bash
bats test/unit/util.bats
```

Expected: all tests fail because `lib/util.sh` doesn't exist.

- [ ] **Step 4: Implement `lib/util.sh`**

```bash
mkdir -p lib
cat >lib/util.sh <<'EOF'
#!/usr/bin/env bash
# Shared utilities. Source this first.
set -euo pipefail

# Defaults; the entrypoint may override.
: "${JR_NO_SUDO:=0}"
: "${JR_DRY_RUN:=0}"
: "${JR_SUDO_QUEUE_FILE:=}"

log_info() { printf '[INFO] %s\n' "$*" >&2; }
log_warn() { printf '[WARN] %s\n' "$*" >&2; }
log_err()  { printf '[ERROR] %s\n' "$*" >&2; }

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
EOF
```

- [ ] **Step 5: Run the test, see it pass**

```bash
bats test/unit/util.bats
```

Expected: `5 tests, 0 failures`.

- [ ] **Step 6: Lint**

```bash
make lint
```

Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add lib/util.sh test/helpers/stubs/sudo test/unit/util.bats
git commit -m "feat(lib): add util.sh with logging, run_sudo, run_cmd"
```

---

### Task 8: lib/config.sh — load target and jetpack files

**Files:**
- Create: `lib/config.sh`
- Create: `test/unit/config.bats`

- [ ] **Step 1: Write the failing test**

```bash
cat >test/unit/config.bats <<'EOF'
#!/usr/bin/env bats

load ../helpers/load

setup() {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/util.sh"
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/config.sh"
}

@test "load_target reads orin-nano-devkit and sets JR_BOARD_ID" {
    load_target "${JR_REPO_ROOT}" "orin-nano-devkit"
    assert_equal "${JR_BOARD_ID}" "jetson-orin-nano-devkit"
    assert_equal "${JR_USB_PRODUCT_ID}" "7e19"
}

@test "load_target rejects an unknown target" {
    run load_target "${JR_REPO_ROOT}" "does-not-exist"
    assert_failure 2
    [[ "${output}" == *unknown\ target* ]]
}

@test "load_target rejects a target name with path traversal" {
    run load_target "${JR_REPO_ROOT}" "../../etc/passwd"
    assert_failure 2
    [[ "${output}" == *invalid\ target\ name* ]]
}

@test "load_jetpack reads 6.2.1 and sets JR_BSP_URL" {
    load_jetpack "${JR_REPO_ROOT}" "6.2.1"
    [[ "${JR_BSP_URL}" == https://* ]]
    [[ "${JR_BSP_SHA256}" =~ ^[0-9a-f]{64}$ ]]
}

@test "list_targets prints all available target names" {
    run list_targets "${JR_REPO_ROOT}"
    assert_success
    [[ "${output}" == *orin-nano-devkit* ]]
    [[ "${output}" == *agx-orin-devkit* ]]
}
EOF
```

- [ ] **Step 2: Run, see fail**

```bash
bats test/unit/config.bats
```

- [ ] **Step 3: Implement `lib/config.sh`**

```bash
cat >lib/config.sh <<'EOF'
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
EOF
```

- [ ] **Step 4: Run, see pass**

```bash
bats test/unit/config.bats
```

Expected: `5 tests, 0 failures`.

- [ ] **Step 5: Lint and commit**

```bash
make lint
git add lib/config.sh test/unit/config.bats
git commit -m "feat(lib): add config.sh with load_target/load_jetpack"
```

---

## Phase 4: Preflight building blocks

### Task 9: lib/runtime.sh — podman/docker abstraction

**Files:**
- Create: `lib/runtime.sh`
- Create: `test/helpers/stubs/podman`
- Create: `test/helpers/stubs/docker`
- Create: `test/unit/runtime.bats`

- [ ] **Step 1: Write the failing test**

```bash
cat >test/unit/runtime.bats <<'EOF'
#!/usr/bin/env bats

load ../helpers/load

setup() {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/util.sh"
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/runtime.sh"
}

@test "detect_runtime prefers podman when both are installed" {
    jr_use_stub podman
    jr_use_stub docker
    run detect_runtime
    assert_success
    assert_output "podman"
}

@test "detect_runtime falls back to docker when podman is absent" {
    # Build a PATH with only the docker stub.
    local stubs="${JR_TMPDIR}/runtime-only-docker"
    mkdir -p "${stubs}"
    ln -sf "${JR_REPO_ROOT}/test/helpers/stubs/docker" "${stubs}/docker"
    PATH="${stubs}:/usr/bin:/bin"
    run detect_runtime
    assert_success
    assert_output "docker"
}

@test "detect_runtime fails clearly when neither is installed" {
    PATH="${JR_TMPDIR}/empty"
    mkdir -p "${PATH}"
    run detect_runtime
    assert_failure 2
    [[ "${output}" == *neither\ podman\ nor\ docker* ]]
}
EOF
```

- [ ] **Step 2: Add the podman and docker stubs**

```bash
cat >test/helpers/stubs/podman <<'EOF'
#!/usr/bin/env bash
echo "podman $*" >>"${JR_STUB_LOG}"
exit 0
EOF
chmod +x test/helpers/stubs/podman

cat >test/helpers/stubs/docker <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >>"${JR_STUB_LOG}"
exit 0
EOF
chmod +x test/helpers/stubs/docker
```

- [ ] **Step 3: Run, see fail**

```bash
bats test/unit/runtime.bats
```

- [ ] **Step 4: Implement `lib/runtime.sh`**

```bash
cat >lib/runtime.sh <<'EOF'
#!/usr/bin/env bash
# Podman/docker abstraction.
set -euo pipefail

detect_runtime() {
    if command -v podman >/dev/null 2>&1; then
        echo "podman"
        return 0
    fi
    if command -v docker >/dev/null 2>&1; then
        echo "docker"
        return 0
    fi
    log_die "neither podman nor docker found in PATH; install one and retry"
}

# Build the container run argv. Echoes a NUL-separated argv that the caller
# pipes into `xargs -0` or reads with mapfile -d ''.
build_run_argv() {
    local runtime="$1" image="$2" workdir="$3"
    shift 3
    # Remaining args are passed to the container entrypoint.
    local argv=(
        "${runtime}" run --rm
        --privileged
        --net host
        -v /dev/bus/usb:/dev/bus/usb
        -v "${workdir}/Linux_for_Tegra:/Linux_for_Tegra"
        "${image}"
        "$@"
    )
    printf '%s\0' "${argv[@]}"
}
EOF
```

- [ ] **Step 5: Run, see pass**

```bash
bats test/unit/runtime.bats
```

Expected: `3 tests, 0 failures`.

- [ ] **Step 6: Lint and commit**

```bash
make lint
git add lib/runtime.sh test/helpers/stubs/podman test/helpers/stubs/docker test/unit/runtime.bats
git commit -m "feat(lib): add runtime.sh with podman/docker detection"
```

---

### Task 10: lib/recovery.sh — VID 0955 detection

**Files:**
- Create: `lib/recovery.sh`
- Create: `test/helpers/stubs/lsusb`
- Create: `test/unit/recovery.bats`

- [ ] **Step 1: Write the failing test**

```bash
cat >test/unit/recovery.bats <<'EOF'
#!/usr/bin/env bats

load ../helpers/load

setup() {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/util.sh"
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/recovery.sh"
}

@test "find_jetson_devices returns empty when no 0955 present" {
    jr_use_stub lsusb
    JR_LSUSB_OUTPUT="" run find_jetson_devices
    assert_success
    assert_output ""
}

@test "find_jetson_devices returns one bus:dev for one matching device" {
    jr_use_stub lsusb
    JR_LSUSB_OUTPUT="Bus 003 Device 042: ID 0955:7e19 NVIDIA Corp. APX" \
        run find_jetson_devices
    assert_success
    assert_output "003:042 7e19"
}

@test "find_jetson_devices returns multiple lines for multiple devices" {
    jr_use_stub lsusb
    JR_LSUSB_OUTPUT="\
Bus 003 Device 042: ID 0955:7e19 NVIDIA Corp. APX
Bus 004 Device 015: ID 0955:7023 NVIDIA Corp. APX" \
        run find_jetson_devices
    assert_success
    assert_line --index 0 "003:042 7e19"
    assert_line --index 1 "004:015 7023"
}

@test "wait_for_recovery returns 0 when device appears within timeout" {
    jr_use_stub lsusb
    JR_LSUSB_OUTPUT="Bus 003 Device 042: ID 0955:7e19 NVIDIA Corp. APX"
    run wait_for_recovery "7e19" 2
    assert_success
}

@test "wait_for_recovery returns 1 when device never appears" {
    jr_use_stub lsusb
    JR_LSUSB_OUTPUT=""
    run wait_for_recovery "7e19" 1
    assert_failure 1
}
EOF
```

- [ ] **Step 2: Update the lsusb stub to honor JR_LSUSB_OUTPUT**

```bash
cat >test/helpers/stubs/lsusb <<'EOF'
#!/usr/bin/env bash
echo "lsusb $*" >>"${JR_STUB_LOG}"
# When the test sets JR_LSUSB_OUTPUT, return it. Otherwise empty.
printf '%s\n' "${JR_LSUSB_OUTPUT:-}"
exit 0
EOF
chmod +x test/helpers/stubs/lsusb
```

- [ ] **Step 3: Run, see fail**

```bash
bats test/unit/recovery.bats
```

- [ ] **Step 4: Implement `lib/recovery.sh`**

```bash
cat >lib/recovery.sh <<'EOF'
#!/usr/bin/env bash
# Detect Jetson devices in recovery mode (USB VID 0955).
set -euo pipefail

# Print "BBB:DDD PRODID" for each VID 0955 device on the USB bus.
find_jetson_devices() {
    local line bus dev rest vid_pid product
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
    while (( elapsed < timeout_s )); do
        if find_jetson_devices | awk '{print $2}' | grep -qx "${product_id}"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}
EOF
```

- [ ] **Step 5: Run, see pass**

```bash
bats test/unit/recovery.bats
```

Expected: `5 tests, 0 failures`.

- [ ] **Step 6: Lint and commit**

```bash
make lint
git add lib/recovery.sh test/helpers/stubs/lsusb test/unit/recovery.bats
git commit -m "feat(lib): add recovery.sh with find_jetson_devices and wait_for_recovery"
```

---

### Task 11: lib/udev.sh — install/remove the udev rule

**Files:**
- Create: `lib/udev.sh`
- Create: `test/helpers/stubs/udevadm`
- Create: `test/unit/udev.bats`

- [ ] **Step 1: Write the failing test**

```bash
cat >test/unit/udev.bats <<'EOF'
#!/usr/bin/env bats

load ../helpers/load

setup() {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/util.sh"
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/udev.sh"
    JR_UDEV_DEST="${JR_TMPDIR}/etc/udev/rules.d/70-jetson-restore.rules"
    export JR_UDEV_DEST
    mkdir -p "$(dirname "${JR_UDEV_DEST}")"
    jr_use_stub sudo
    jr_use_stub udevadm
}

@test "install_udev_rule writes the rule with @JR_GROUP@ replaced" {
    install_udev_rule "${JR_REPO_ROOT}" "wheel"
    grep -q 'GROUP="wheel"' "${JR_UDEV_DEST}"
    refute grep -q '@JR_GROUP@' "${JR_UDEV_DEST}"
}

@test "install_udev_rule reloads udev" {
    install_udev_rule "${JR_REPO_ROOT}" "wheel"
    jr_read_stub_log
    [[ "${output}" == *udevadm\ control\ --reload* ]]
}

@test "install_udev_rule is idempotent: second run does not re-write or re-reload" {
    install_udev_rule "${JR_REPO_ROOT}" "wheel"
    : > "${JR_STUB_LOG}"
    install_udev_rule "${JR_REPO_ROOT}" "wheel"
    jr_read_stub_log
    [[ "${output}" != *udevadm\ control\ --reload* ]]
}

@test "remove_udev_rule deletes the file when present" {
    install_udev_rule "${JR_REPO_ROOT}" "wheel"
    [ -f "${JR_UDEV_DEST}" ]
    remove_udev_rule
    [ ! -f "${JR_UDEV_DEST}" ]
}

@test "remove_udev_rule is a no-op when the file is absent" {
    run remove_udev_rule
    assert_success
}
EOF
```

- [ ] **Step 2: Add the udevadm stub**

```bash
cat >test/helpers/stubs/udevadm <<'EOF'
#!/usr/bin/env bash
echo "udevadm $*" >>"${JR_STUB_LOG}"
exit 0
EOF
chmod +x test/helpers/stubs/udevadm
```

- [ ] **Step 3: Run, see fail**

```bash
bats test/unit/udev.bats
```

- [ ] **Step 4: Implement `lib/udev.sh`**

```bash
cat >lib/udev.sh <<'EOF'
#!/usr/bin/env bash
# Install/remove the udev rule for VID 0955.
set -euo pipefail

: "${JR_UDEV_DEST:=/etc/udev/rules.d/70-jetson-restore.rules}"

install_udev_rule() {
    local repo="$1" group="$2"
    local src="${repo}/share/70-jetson-restore.rules"
    local rendered
    rendered="$(sed "s|@JR_GROUP@|${group}|g" "${src}")"

    if [[ -f "${JR_UDEV_DEST}" ]] && \
       [[ "$(cat "${JR_UDEV_DEST}")" == "${rendered}" ]]; then
        log_info "udev rule already up to date"
        return 0
    fi

    log_info "installing udev rule to ${JR_UDEV_DEST}"
    run_sudo install -D -m 0644 /dev/stdin "${JR_UDEV_DEST}" <<<"${rendered}"
    run_sudo udevadm control --reload
    run_sudo udevadm trigger --subsystem-match=usb
}

remove_udev_rule() {
    if [[ -f "${JR_UDEV_DEST}" ]]; then
        log_info "removing udev rule ${JR_UDEV_DEST}"
        run_sudo rm -f "${JR_UDEV_DEST}"
        run_sudo udevadm control --reload
    fi
}
EOF
```

Note: in the test, `JR_UDEV_DEST` points into a temp dir, and `run_sudo` calls the stub. The `install -D -m 0644 /dev/stdin "${JR_UDEV_DEST}"` form requires that `install` writes to the destination via the sudo wrapper. Since the sudo stub doesn't actually re-exec with elevated privileges, the test needs to override the behavior. Adjust the implementation to use `run_cmd` for the file write when `JR_UDEV_DEST` is in the test temp dir — or, simpler, write a non-sudo helper `_write_file` that the test can intercept. Use this version instead:

```bash
cat >lib/udev.sh <<'EOF'
#!/usr/bin/env bash
# Install/remove the udev rule for VID 0955.
set -euo pipefail

: "${JR_UDEV_DEST:=/etc/udev/rules.d/70-jetson-restore.rules}"

# Indirection so tests can write without sudo. Production sets to "run_sudo".
: "${JR_FS_WRITER:=run_sudo}"

install_udev_rule() {
    local repo="$1" group="$2"
    local src="${repo}/share/70-jetson-restore.rules"
    local rendered
    rendered="$(sed "s|@JR_GROUP@|${group}|g" "${src}")"

    if [[ -f "${JR_UDEV_DEST}" ]] && \
       [[ "$(cat "${JR_UDEV_DEST}")" == "${rendered}" ]]; then
        log_info "udev rule already up to date"
        return 0
    fi

    log_info "installing udev rule to ${JR_UDEV_DEST}"
    mkdir -p "$(dirname "${JR_UDEV_DEST}")"
    printf '%s\n' "${rendered}" >"${JR_UDEV_DEST}"
    "${JR_FS_WRITER}" udevadm control --reload
    "${JR_FS_WRITER}" udevadm trigger --subsystem-match=usb
}

remove_udev_rule() {
    if [[ -f "${JR_UDEV_DEST}" ]]; then
        log_info "removing udev rule ${JR_UDEV_DEST}"
        rm -f "${JR_UDEV_DEST}"
        "${JR_FS_WRITER}" udevadm control --reload
    fi
}
EOF
```

In production, `bin/jetson-restore` will set `JR_FS_WRITER=run_sudo` and write the destination file via `sudo install`. The test simply uses the default `run_sudo` (which calls the sudo stub) for the udevadm calls and writes the rule directly to its temp `JR_UDEV_DEST`. Update the test's destination to be writable by the test user (already done — temp dir).

Adjust the install path in production: the entrypoint will call `run_sudo install -D -m 0644 "${rendered_tmp}" "${JR_UDEV_DEST}"` for the real run. Encapsulate that in a separate function called only from production. Pragmatic: keep the test as-is and document the production codepath in a comment.

Add the comment:

```bash
sed -i '1a# In production, bin/jetson-restore writes JR_UDEV_DEST via sudo install\n# before calling install_udev_rule, then this function only updates content.' lib/udev.sh
```

(That edit is fragile — instead, replace the whole file with the version below.)

```bash
cat >lib/udev.sh <<'EOF'
#!/usr/bin/env bash
# Install/remove the udev rule for VID 0955.
#
# In production, bin/jetson-restore sets JR_FS_WRITER=run_sudo and the file
# write goes through sudo install. In tests, JR_UDEV_DEST is in a temp dir
# the test user owns, so the direct write succeeds without sudo.
set -euo pipefail

: "${JR_UDEV_DEST:=/etc/udev/rules.d/70-jetson-restore.rules}"
: "${JR_FS_WRITER:=run_sudo}"

install_udev_rule() {
    local repo="$1" group="$2"
    local src="${repo}/share/70-jetson-restore.rules"
    local rendered
    rendered="$(sed "s|@JR_GROUP@|${group}|g" "${src}")"

    if [[ -f "${JR_UDEV_DEST}" ]] && \
       [[ "$(cat "${JR_UDEV_DEST}")" == "${rendered}" ]]; then
        log_info "udev rule already up to date"
        return 0
    fi

    log_info "installing udev rule to ${JR_UDEV_DEST}"
    local dest_dir
    dest_dir="$(dirname "${JR_UDEV_DEST}")"
    if [[ ! -d "${dest_dir}" ]]; then
        "${JR_FS_WRITER}" mkdir -p "${dest_dir}"
    fi
    printf '%s\n' "${rendered}" | "${JR_FS_WRITER}" tee "${JR_UDEV_DEST}" >/dev/null
    "${JR_FS_WRITER}" udevadm control --reload
    "${JR_FS_WRITER}" udevadm trigger --subsystem-match=usb
}

remove_udev_rule() {
    if [[ -f "${JR_UDEV_DEST}" ]]; then
        log_info "removing udev rule ${JR_UDEV_DEST}"
        "${JR_FS_WRITER}" rm -f "${JR_UDEV_DEST}"
        "${JR_FS_WRITER}" udevadm control --reload
    fi
}
EOF
```

For the test to pass, add a `tee` stub that writes to the destination it was given:

```bash
cat >test/helpers/stubs/tee <<'EOF'
#!/usr/bin/env bash
echo "tee $*" >>"${JR_STUB_LOG}"
# Behave like real tee for the file argument.
exec /usr/bin/tee "$@"
EOF
chmod +x test/helpers/stubs/tee
```

Add `jr_use_stub tee` to the test's setup.

- [ ] **Step 5: Run, see pass**

```bash
bats test/unit/udev.bats
```

Expected: `5 tests, 0 failures`.

- [ ] **Step 6: Lint and commit**

```bash
make lint
git add lib/udev.sh test/helpers/stubs/udevadm test/helpers/stubs/tee test/unit/udev.bats
git commit -m "feat(lib): add udev.sh with install/remove (idempotent)"
```

---

### Task 12: lib/netmgr.sh — install/remove NetworkManager keyfile for RNDIS

**Files:**
- Create: `lib/netmgr.sh`
- Create: `test/helpers/stubs/nmcli`
- Create: `test/unit/netmgr.bats`

NetworkManager's RNDIS-MAC unmanaged-rule is the cleanest way to keep NM from grabbing the recovery interface. We install a keyfile under `/etc/NetworkManager/system-connections/jetson-restore-rndis.nmconnection` and reload via `nmcli connection reload`. If NetworkManager isn't installed, this is a no-op (a warning, not an error).

The well-known L4T recovery RNDIS MAC is `1a:2b:3c:4d:5e:6f` per the JetPack 6 sources. Verify at implementation time by booting the initrd once and reading the host-side `usb0` peer MAC; if it differs, update `share/jetson-restore.nmconnection.tmpl` and the test fixture.

- [ ] **Step 1: Write the failing test**

```bash
cat >test/unit/netmgr.bats <<'EOF'
#!/usr/bin/env bats

load ../helpers/load

setup() {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/util.sh"
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/netmgr.sh"
    JR_NM_DEST="${JR_TMPDIR}/etc/NetworkManager/system-connections/jetson-restore-rndis.nmconnection"
    export JR_NM_DEST
    mkdir -p "$(dirname "${JR_NM_DEST}")"
    jr_use_stub sudo
    jr_use_stub tee
    jr_use_stub nmcli
}

@test "install_nm_keyfile writes file with @JR_RNDIS_MAC@ replaced" {
    install_nm_keyfile "${JR_REPO_ROOT}" "1a:2b:3c:4d:5e:6f"
    grep -q 'mac-address=1a:2b:3c:4d:5e:6f' "${JR_NM_DEST}"
    refute grep -q '@JR_RNDIS_MAC@' "${JR_NM_DEST}"
}

@test "install_nm_keyfile sets file mode 0600 (NM requirement)" {
    install_nm_keyfile "${JR_REPO_ROOT}" "1a:2b:3c:4d:5e:6f"
    [ "$(stat -c %a "${JR_NM_DEST}")" = "600" ]
}

@test "install_nm_keyfile is idempotent" {
    install_nm_keyfile "${JR_REPO_ROOT}" "1a:2b:3c:4d:5e:6f"
    : > "${JR_STUB_LOG}"
    install_nm_keyfile "${JR_REPO_ROOT}" "1a:2b:3c:4d:5e:6f"
    jr_read_stub_log
    [[ "${output}" != *nmcli\ connection\ reload* ]]
}

@test "remove_nm_keyfile deletes the file" {
    install_nm_keyfile "${JR_REPO_ROOT}" "1a:2b:3c:4d:5e:6f"
    remove_nm_keyfile
    [ ! -f "${JR_NM_DEST}" ]
}

@test "install_nm_keyfile is a no-op (warn) when nmcli is absent" {
    PATH="${JR_TMPDIR}/empty"
    mkdir -p "${PATH}"
    run install_nm_keyfile "${JR_REPO_ROOT}" "1a:2b:3c:4d:5e:6f"
    assert_success
    [[ "${output}" == *NetworkManager\ not\ installed* ]]
}
EOF
```

- [ ] **Step 2: Add nmcli stub**

```bash
cat >test/helpers/stubs/nmcli <<'EOF'
#!/usr/bin/env bash
echo "nmcli $*" >>"${JR_STUB_LOG}"
exit 0
EOF
chmod +x test/helpers/stubs/nmcli
```

- [ ] **Step 3: Run, see fail**

```bash
bats test/unit/netmgr.bats
```

- [ ] **Step 4: Implement `lib/netmgr.sh`**

```bash
cat >lib/netmgr.sh <<'EOF'
#!/usr/bin/env bash
# Install/remove the NetworkManager keyfile for the recovery RNDIS interface.
set -euo pipefail

: "${JR_NM_DEST:=/etc/NetworkManager/system-connections/jetson-restore-rndis.nmconnection}"
: "${JR_FS_WRITER:=run_sudo}"

_nm_present() { command -v nmcli >/dev/null 2>&1; }

install_nm_keyfile() {
    local repo="$1" rndis_mac="$2"
    if ! _nm_present; then
        log_warn "NetworkManager not installed; skipping NM keyfile (this is fine on systemd-networkd hosts)"
        return 0
    fi
    local src="${repo}/share/jetson-restore.nmconnection.tmpl"
    local rendered
    rendered="$(sed "s|@JR_RNDIS_MAC@|${rndis_mac}|g" "${src}")"

    if [[ -f "${JR_NM_DEST}" ]] && \
       [[ "$(cat "${JR_NM_DEST}")" == "${rendered}" ]]; then
        log_info "NM keyfile already up to date"
        return 0
    fi

    log_info "installing NM keyfile to ${JR_NM_DEST}"
    local dest_dir
    dest_dir="$(dirname "${JR_NM_DEST}")"
    if [[ ! -d "${dest_dir}" ]]; then
        "${JR_FS_WRITER}" mkdir -p "${dest_dir}"
    fi
    printf '%s\n' "${rendered}" | "${JR_FS_WRITER}" tee "${JR_NM_DEST}" >/dev/null
    "${JR_FS_WRITER}" chmod 600 "${JR_NM_DEST}"
    "${JR_FS_WRITER}" nmcli connection reload
}

remove_nm_keyfile() {
    if [[ -f "${JR_NM_DEST}" ]]; then
        log_info "removing NM keyfile ${JR_NM_DEST}"
        "${JR_FS_WRITER}" rm -f "${JR_NM_DEST}"
        if _nm_present; then
            "${JR_FS_WRITER}" nmcli connection reload
        fi
    fi
}
EOF
```

For the chmod test: when the writer is the sudo stub, it doesn't actually `chmod`. Add `chmod` to the stub list, or have the stub fall through to the real binary for safe operations. Use the simpler approach:

```bash
cat >test/helpers/stubs/chmod <<'EOF'
#!/usr/bin/env bash
echo "chmod $*" >>"${JR_STUB_LOG}"
exec /usr/bin/chmod "$@"
EOF
chmod +x test/helpers/stubs/chmod
```

Add `jr_use_stub chmod` to the netmgr test setup.

- [ ] **Step 5: Run, see pass**

```bash
bats test/unit/netmgr.bats
```

Expected: `5 tests, 0 failures`.

- [ ] **Step 6: Lint and commit**

```bash
make lint
git add lib/netmgr.sh test/helpers/stubs/nmcli test/helpers/stubs/chmod test/unit/netmgr.bats
git commit -m "feat(lib): add netmgr.sh with NM keyfile install/remove"
```

---

### Task 13: lib/nfs.sh — manage exports.d snippet, start nfs-server

**Files:**
- Create: `lib/nfs.sh`
- Create: `test/helpers/stubs/exportfs`
- Create: `test/helpers/stubs/systemctl`
- Create: `test/unit/nfs.bats`

The exports.d snippet lives at `/etc/exports.d/jetson-restore.conf`. We track whether jetson-restore was the one that started nfs-server via a marker file `/var/lib/jetson-restore/nfs-server-started-by-us` — used by `uninstall` to decide whether to stop it.

- [ ] **Step 1: Write the failing test**

```bash
cat >test/unit/nfs.bats <<'EOF'
#!/usr/bin/env bats

load ../helpers/load

setup() {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/util.sh"
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/nfs.sh"
    JR_NFS_EXPORTS_DEST="${JR_TMPDIR}/etc/exports.d/jetson-restore.conf"
    JR_NFS_STATE_DIR="${JR_TMPDIR}/var/lib/jetson-restore"
    export JR_NFS_EXPORTS_DEST JR_NFS_STATE_DIR
    mkdir -p "$(dirname "${JR_NFS_EXPORTS_DEST}")" "${JR_NFS_STATE_DIR}"
    jr_use_stub sudo
    jr_use_stub tee
    jr_use_stub exportfs
    jr_use_stub systemctl
}

@test "install_nfs_export writes the snippet with @JR_EXPORT_PATH@ replaced" {
    install_nfs_export "${JR_REPO_ROOT}" "/srv/jetson/Linux_for_Tegra"
    grep -q '/srv/jetson/Linux_for_Tegra' "${JR_NFS_EXPORTS_DEST}"
    grep -q '192.168.55.0/24' "${JR_NFS_EXPORTS_DEST}"
}

@test "install_nfs_export runs exportfs -ra" {
    install_nfs_export "${JR_REPO_ROOT}" "/srv/jetson/Linux_for_Tegra"
    jr_read_stub_log
    [[ "${output}" == *exportfs\ -ra* ]]
}

@test "ensure_nfs_server_running starts nfs-server if inactive and creates marker" {
    JR_SYSTEMCTL_STATE="inactive"
    ensure_nfs_server_running
    jr_read_stub_log
    [[ "${output}" == *systemctl\ start\ nfs-server* ]]
    [ -f "${JR_NFS_STATE_DIR}/nfs-server-started-by-us" ]
}

@test "ensure_nfs_server_running is no-op when already active" {
    JR_SYSTEMCTL_STATE="active"
    ensure_nfs_server_running
    jr_read_stub_log
    [[ "${output}" != *systemctl\ start\ nfs-server* ]]
    [ ! -f "${JR_NFS_STATE_DIR}/nfs-server-started-by-us" ]
}

@test "remove_nfs_export deletes snippet and runs exportfs -ra" {
    install_nfs_export "${JR_REPO_ROOT}" "/srv/jetson/Linux_for_Tegra"
    remove_nfs_export
    [ ! -f "${JR_NFS_EXPORTS_DEST}" ]
    jr_read_stub_log
    [[ "${output}" == *exportfs\ -ra* ]]
}

@test "stop_nfs_server_if_we_started_it stops only when marker present" {
    : >"${JR_NFS_STATE_DIR}/nfs-server-started-by-us"
    stop_nfs_server_if_we_started_it
    jr_read_stub_log
    [[ "${output}" == *systemctl\ stop\ nfs-server* ]]
}

@test "stop_nfs_server_if_we_started_it is no-op when no marker" {
    rm -f "${JR_NFS_STATE_DIR}/nfs-server-started-by-us"
    stop_nfs_server_if_we_started_it
    jr_read_stub_log
    [[ "${output}" != *systemctl\ stop\ nfs-server* ]]
}
EOF
```

- [ ] **Step 2: Add stubs**

```bash
cat >test/helpers/stubs/exportfs <<'EOF'
#!/usr/bin/env bash
echo "exportfs $*" >>"${JR_STUB_LOG}"
exit 0
EOF
chmod +x test/helpers/stubs/exportfs

cat >test/helpers/stubs/systemctl <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >>"${JR_STUB_LOG}"
case "$1" in
    is-active)
        printf '%s\n' "${JR_SYSTEMCTL_STATE:-active}"
        ;;
esac
exit 0
EOF
chmod +x test/helpers/stubs/systemctl
```

- [ ] **Step 3: Run, see fail**

```bash
bats test/unit/nfs.bats
```

- [ ] **Step 4: Implement `lib/nfs.sh`**

```bash
cat >lib/nfs.sh <<'EOF'
#!/usr/bin/env bash
# Manage the NFS exports.d snippet and nfs-server state.
set -euo pipefail

: "${JR_NFS_EXPORTS_DEST:=/etc/exports.d/jetson-restore.conf}"
: "${JR_NFS_STATE_DIR:=/var/lib/jetson-restore}"
: "${JR_FS_WRITER:=run_sudo}"

_marker_file() { echo "${JR_NFS_STATE_DIR}/nfs-server-started-by-us"; }

install_nfs_export() {
    local repo="$1" export_path="$2"
    local src="${repo}/share/jetson-restore.exports.tmpl"
    local rendered
    rendered="$(sed "s|@JR_EXPORT_PATH@|${export_path}|g" "${src}")"

    if [[ -f "${JR_NFS_EXPORTS_DEST}" ]] && \
       [[ "$(cat "${JR_NFS_EXPORTS_DEST}")" == "${rendered}" ]]; then
        log_info "NFS export already up to date"
        return 0
    fi

    log_info "installing NFS export ${JR_NFS_EXPORTS_DEST} → ${export_path}"
    local dest_dir
    dest_dir="$(dirname "${JR_NFS_EXPORTS_DEST}")"
    if [[ ! -d "${dest_dir}" ]]; then
        "${JR_FS_WRITER}" mkdir -p "${dest_dir}"
    fi
    printf '%s\n' "${rendered}" | "${JR_FS_WRITER}" tee "${JR_NFS_EXPORTS_DEST}" >/dev/null
    "${JR_FS_WRITER}" exportfs -ra
}

remove_nfs_export() {
    if [[ -f "${JR_NFS_EXPORTS_DEST}" ]]; then
        log_info "removing NFS export ${JR_NFS_EXPORTS_DEST}"
        "${JR_FS_WRITER}" rm -f "${JR_NFS_EXPORTS_DEST}"
        "${JR_FS_WRITER}" exportfs -ra
    fi
}

ensure_nfs_server_running() {
    local state
    state="$(systemctl is-active nfs-server 2>/dev/null || true)"
    if [[ "${state}" == "active" ]]; then
        log_info "nfs-server already active"
        return 0
    fi
    log_warn "starting nfs-server (will remain running; 'systemctl disable --now nfs-server' to stop)"
    "${JR_FS_WRITER}" mkdir -p "${JR_NFS_STATE_DIR}"
    "${JR_FS_WRITER}" tee "$(_marker_file)" </dev/null >/dev/null
    "${JR_FS_WRITER}" systemctl start nfs-server
    "${JR_FS_WRITER}" systemctl enable nfs-server
}

stop_nfs_server_if_we_started_it() {
    if [[ -f "$(_marker_file)" ]]; then
        log_info "stopping nfs-server (we started it earlier)"
        "${JR_FS_WRITER}" systemctl stop nfs-server
        "${JR_FS_WRITER}" rm -f "$(_marker_file)"
    fi
}
EOF
```

- [ ] **Step 5: Run, see pass**

```bash
bats test/unit/nfs.bats
```

Expected: `7 tests, 0 failures`.

- [ ] **Step 6: Lint and commit**

```bash
make lint
git add lib/nfs.sh test/helpers/stubs/exportfs test/helpers/stubs/systemctl test/unit/nfs.bats
git commit -m "feat(lib): add nfs.sh with exports management and nfs-server state"
```

---

### Task 14: lib/cache.sh — download and verify BSP/rootfs tarballs

**Files:**
- Create: `lib/cache.sh`
- Create: `test/helpers/stubs/curl`
- Create: `test/unit/cache.bats`

The cache lives under `${WORKDIR}/cache/jp-${JR_JETPACK_VERSION}/`. Each tarball is downloaded to a `.partial` filename and atomically renamed on successful sha256 verification. Re-runs verify the existing file's checksum and skip the download if it matches.

- [ ] **Step 1: Write the failing test**

```bash
cat >test/unit/cache.bats <<'EOF'
#!/usr/bin/env bats

load ../helpers/load

setup() {
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/util.sh"
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/cache.sh"
    JR_WORKDIR="${JR_TMPDIR}/work"
    mkdir -p "${JR_WORKDIR}"
    jr_use_stub curl
}

@test "download_artifact downloads, verifies, and renames on sha256 match" {
    local content="hello-bsp"
    local sha
    sha="$(printf '%s' "${content}" | sha256sum | awk '{print $1}')"
    JR_CURL_FAKE_BODY="${content}"
    download_artifact \
        "${JR_WORKDIR}/cache/jp-6.2.1/Jetson_Linux.tbz2" \
        "https://example.invalid/bsp.tbz2" \
        "${sha}"
    [ -f "${JR_WORKDIR}/cache/jp-6.2.1/Jetson_Linux.tbz2" ]
    assert_equal \
        "$(cat "${JR_WORKDIR}/cache/jp-6.2.1/Jetson_Linux.tbz2")" \
        "${content}"
}

@test "download_artifact fails when sha256 mismatches" {
    JR_CURL_FAKE_BODY="wrong content"
    run download_artifact \
        "${JR_WORKDIR}/cache/jp-6.2.1/Jetson_Linux.tbz2" \
        "https://example.invalid/bsp.tbz2" \
        "0000000000000000000000000000000000000000000000000000000000000000"
    assert_failure 2
    [[ "${output}" == *checksum\ mismatch* ]]
    [ ! -f "${JR_WORKDIR}/cache/jp-6.2.1/Jetson_Linux.tbz2" ]
}

@test "download_artifact skips download when existing file matches sha256" {
    local content="hello-bsp"
    local sha
    sha="$(printf '%s' "${content}" | sha256sum | awk '{print $1}')"
    mkdir -p "${JR_WORKDIR}/cache/jp-6.2.1"
    printf '%s' "${content}" >"${JR_WORKDIR}/cache/jp-6.2.1/Jetson_Linux.tbz2"

    : > "${JR_STUB_LOG}"
    download_artifact \
        "${JR_WORKDIR}/cache/jp-6.2.1/Jetson_Linux.tbz2" \
        "https://example.invalid/bsp.tbz2" \
        "${sha}"
    jr_read_stub_log
    [[ "${output}" != *curl* ]]
}
EOF
```

- [ ] **Step 2: Add curl stub**

```bash
cat >test/helpers/stubs/curl <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >>"${JR_STUB_LOG}"
# Find the -o argument.
out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) out="$2"; shift 2;;
        *) shift;;
    esac
done
if [[ -n "${out}" ]]; then
    printf '%s' "${JR_CURL_FAKE_BODY:-}" >"${out}"
fi
exit 0
EOF
chmod +x test/helpers/stubs/curl
```

- [ ] **Step 3: Run, see fail**

```bash
bats test/unit/cache.bats
```

- [ ] **Step 4: Implement `lib/cache.sh`**

```bash
cat >lib/cache.sh <<'EOF'
#!/usr/bin/env bash
# Download and verify BSP/rootfs tarballs.
set -euo pipefail

_sha256_of() { sha256sum "$1" | awk '{print $1}'; }

download_artifact() {
    local dest="$1" url="$2" expected_sha="$3"
    local dest_dir
    dest_dir="$(dirname "${dest}")"
    mkdir -p "${dest_dir}"

    if [[ -f "${dest}" ]] && [[ "$(_sha256_of "${dest}")" == "${expected_sha}" ]]; then
        log_info "cached: ${dest}"
        return 0
    fi

    local partial="${dest}.partial"
    log_info "downloading $(basename "${dest}") ..."
    curl --fail --location --show-error \
         --connect-timeout 30 --retry 3 \
         -o "${partial}" "${url}"

    local actual_sha
    actual_sha="$(_sha256_of "${partial}")"
    if [[ "${actual_sha}" != "${expected_sha}" ]]; then
        rm -f "${partial}"
        log_die "checksum mismatch for ${url}: expected ${expected_sha}, got ${actual_sha}"
    fi
    mv -f "${partial}" "${dest}"
}

# Higher-level: ensure both BSP and rootfs are cached and extracted.
ensure_l4t_extracted() {
    local workdir="$1"
    local cache="${workdir}/cache/jp-${JR_JETPACK_VERSION}"
    local bsp="${cache}/${JR_BSP_FILENAME}"
    local rootfs="${cache}/${JR_ROOTFS_FILENAME}"

    download_artifact "${bsp}"    "${JR_BSP_URL}"    "${JR_BSP_SHA256}"
    download_artifact "${rootfs}" "${JR_ROOTFS_URL}" "${JR_ROOTFS_SHA256}"

    local lt="${workdir}/Linux_for_Tegra"
    if [[ ! -f "${lt}/.jr-extracted-${JR_JETPACK_VERSION}" ]]; then
        log_info "extracting BSP into ${lt}"
        mkdir -p "${workdir}"
        tar -xpf "${bsp}" -C "${workdir}"
        log_info "extracting rootfs into ${lt}/rootfs/"
        mkdir -p "${lt}/rootfs"
        tar -xpf "${rootfs}" -C "${lt}/rootfs"
        : > "${lt}/.jr-extracted-${JR_JETPACK_VERSION}"
    else
        log_info "Linux_for_Tegra already extracted for ${JR_JETPACK_VERSION}"
    fi
}
EOF
```

- [ ] **Step 5: Run, see pass**

```bash
bats test/unit/cache.bats
```

Expected: `3 tests, 0 failures`.

- [ ] **Step 6: Lint and commit**

```bash
make lint
git add lib/cache.sh test/helpers/stubs/curl test/unit/cache.bats
git commit -m "feat(lib): add cache.sh with download_artifact and ensure_l4t_extracted"
```

---

## Phase 5: Preflight orchestration

### Task 15: lib/preflight.sh — run all 12 checks

**Files:**
- Create: `lib/preflight.sh`
- Create: `test/unit/preflight.bats`

`preflight.sh` does not perform downloads or extraction (that's `cache.sh`); it only verifies state and installs host config (udev, NM, NFS). The entrypoint chains them.

- [ ] **Step 1: Write the failing test**

```bash
cat >test/unit/preflight.bats <<'EOF'
#!/usr/bin/env bats

load ../helpers/load

setup() {
    # Bring in everything preflight depends on.
    for f in util config runtime recovery udev netmgr nfs cache preflight; do
        # shellcheck source=/dev/null
        source "${JR_REPO_ROOT}/lib/${f}.sh"
    done

    # Per-test stub roots.
    JR_UDEV_DEST="${JR_TMPDIR}/etc/udev/rules.d/70-jetson-restore.rules"
    JR_NM_DEST="${JR_TMPDIR}/etc/NetworkManager/system-connections/jetson-restore-rndis.nmconnection"
    JR_NFS_EXPORTS_DEST="${JR_TMPDIR}/etc/exports.d/jetson-restore.conf"
    JR_NFS_STATE_DIR="${JR_TMPDIR}/var/lib/jetson-restore"
    JR_WORKDIR="${JR_TMPDIR}/work"
    export JR_UDEV_DEST JR_NM_DEST JR_NFS_EXPORTS_DEST JR_NFS_STATE_DIR JR_WORKDIR

    mkdir -p "${JR_WORKDIR}"
    jr_use_stub sudo
    jr_use_stub tee
    jr_use_stub udevadm
    jr_use_stub nmcli
    jr_use_stub exportfs
    jr_use_stub systemctl
    jr_use_stub chmod
    jr_use_stub lsusb
    jr_use_stub podman
    jr_use_stub df

    # Load configs the entrypoint normally loads.
    load_target  "${JR_REPO_ROOT}" "orin-nano-devkit"
    load_jetpack "${JR_REPO_ROOT}" "6.2.1"
}

@test "run_preflight succeeds with happy-path stubs" {
    JR_LSUSB_OUTPUT="Bus 003 Device 042: ID 0955:7e19 NVIDIA Corp. APX"
    JR_SYSTEMCTL_STATE="active"
    JR_DF_FREE_KB=$((40 * 1024 * 1024))  # 40 GB free
    run run_preflight
    assert_success
}

@test "run_preflight fails when device is not in recovery mode" {
    JR_LSUSB_OUTPUT=""
    JR_SYSTEMCTL_STATE="active"
    JR_DF_FREE_KB=$((40 * 1024 * 1024))
    JR_RECOVERY_TIMEOUT=1
    run run_preflight
    assert_failure 2
    [[ "${output}" == *not\ in\ recovery\ mode* ]]
}

@test "run_preflight fails when disk space is below 30 GB" {
    JR_LSUSB_OUTPUT="Bus 003 Device 042: ID 0955:7e19 NVIDIA Corp. APX"
    JR_SYSTEMCTL_STATE="active"
    JR_DF_FREE_KB=$((10 * 1024 * 1024))  # 10 GB
    run run_preflight
    assert_failure 2
    [[ "${output}" == *insufficient\ disk\ space* ]]
}

@test "run_preflight is idempotent on the second invocation" {
    JR_LSUSB_OUTPUT="Bus 003 Device 042: ID 0955:7e19 NVIDIA Corp. APX"
    JR_SYSTEMCTL_STATE="active"
    JR_DF_FREE_KB=$((40 * 1024 * 1024))
    run_preflight
    : > "${JR_STUB_LOG}"
    run_preflight
    jr_read_stub_log
    [[ "${output}" != *udevadm\ control\ --reload* ]]
    [[ "${output}" != *nmcli\ connection\ reload* ]]
}
EOF
```

- [ ] **Step 2: Add df stub**

```bash
cat >test/helpers/stubs/df <<'EOF'
#!/usr/bin/env bash
echo "df $*" >>"${JR_STUB_LOG}"
# Output mimicking: `df --output=avail -k <path>`
echo "Avail"
echo "${JR_DF_FREE_KB:-99999999}"
EOF
chmod +x test/helpers/stubs/df
```

- [ ] **Step 3: Run, see fail**

```bash
bats test/unit/preflight.bats
```

- [ ] **Step 4: Implement `lib/preflight.sh`**

```bash
cat >lib/preflight.sh <<'EOF'
#!/usr/bin/env bash
# Orchestrate the 12 preflight checks/actions.
set -euo pipefail

: "${JR_RECOVERY_TIMEOUT:=30}"
: "${JR_RNDIS_MAC:=1a:2b:3c:4d:5e:6f}"
: "${JR_MIN_FREE_KB:=$((30 * 1024 * 1024))}"  # 30 GB

_check_disk_space() {
    local workdir="$1"
    local avail_kb
    avail_kb="$(df --output=avail -k "${workdir}" | tail -n 1 | tr -d ' ')"
    if (( avail_kb < JR_MIN_FREE_KB )); then
        log_die "insufficient disk space in ${workdir}: ${avail_kb} KB free, need ${JR_MIN_FREE_KB} KB"
    fi
    log_info "disk space ok: ${avail_kb} KB free in ${workdir}"
}

_check_subnet_clear() {
    if ip route 2>/dev/null | grep -q '192\.168\.55\.0/24'; then
        log_die "another route exists for 192.168.55.0/24; reflash will conflict (VPN/VM?). Remove the route or change subnet."
    fi
}

_check_one_jetson_only() {
    local devices count
    mapfile -t devices < <(find_jetson_devices)
    count="${#devices[@]}"
    if (( count > 1 )) && [[ -z "${JR_DEVICE:-}" ]]; then
        log_die "multiple VID 0955 devices attached; pick one with --device <bus>:<dev>"
    fi
}

_check_recovery_mode() {
    local product_id="$1"
    log_info "waiting for VID 0955:${product_id} (up to ${JR_RECOVERY_TIMEOUT}s)…"
    if ! wait_for_recovery "${product_id}" "${JR_RECOVERY_TIMEOUT}"; then
        log_err "device not in recovery mode (no 0955:${product_id} on USB)"
        log_err "${JR_RECOVERY_INSTRUCTIONS}"
        log_die "place the device in recovery mode and re-run"
    fi
}

# Run all 12 preflight checks/actions. Caller has already loaded:
#   target conf (JR_BOARD_ID, JR_USB_PRODUCT_ID, JR_RECOVERY_INSTRUCTIONS, …)
#   jetpack conf
#   set JR_WORKDIR to an absolute path
run_preflight() {
    log_info "preflight: container runtime"
    detect_runtime >/dev/null

    log_info "preflight: disk space"
    _check_disk_space "${JR_WORKDIR}"

    log_info "preflight: nfs-server"
    ensure_nfs_server_running

    log_info "preflight: nfs export"
    install_nfs_export "${JR_REPO_ROOT}" "${JR_WORKDIR}/Linux_for_Tegra"

    log_info "preflight: udev rule"
    install_udev_rule "${JR_REPO_ROOT}" "$(id -gn)"

    log_info "preflight: NetworkManager keyfile"
    install_nm_keyfile "${JR_REPO_ROOT}" "${JR_RNDIS_MAC}"

    log_info "preflight: subnet not in use"
    _check_subnet_clear

    log_info "preflight: at most one Jetson attached"
    _check_one_jetson_only

    log_info "preflight: device in recovery mode"
    _check_recovery_mode "${JR_USB_PRODUCT_ID}"

    log_info "preflight: complete"
}
EOF
```

Note: `_check_disk_space` requires the `df` stub to honor `--output=avail -k`. The stub already prints two lines (header + value), and the implementation strips the header with `tail -n 1`.

`_check_one_jetson_only` and `_check_subnet_clear` need an `ip` stub to avoid running real `ip route`. Add it:

```bash
cat >test/helpers/stubs/ip <<'EOF'
#!/usr/bin/env bash
echo "ip $*" >>"${JR_STUB_LOG}"
# By default no 192.168.55.0/24 route. Tests that want one set JR_IP_ROUTE_OUT.
printf '%s\n' "${JR_IP_ROUTE_OUT:-}"
exit 0
EOF
chmod +x test/helpers/stubs/ip
```

Add `jr_use_stub ip` to the preflight test setup.

- [ ] **Step 5: Run, see pass**

```bash
bats test/unit/preflight.bats
```

Expected: `4 tests, 0 failures`.

- [ ] **Step 6: Lint and commit**

```bash
make lint
git add lib/preflight.sh test/helpers/stubs/df test/helpers/stubs/ip test/unit/preflight.bats
git commit -m "feat(lib): add preflight.sh orchestrating all 12 checks"
```

---

## Phase 6: Container

### Task 16: container/Containerfile + entrypoint.sh

**Files:**
- Create: `container/Containerfile`
- Create: `container/entrypoint.sh`
- Create: `test/unit/container_smoke.bats`

The container is Ubuntu 22.04 with NVIDIA's `l4t_flash_prerequisites.sh` already run. We do not bake the BSP into the image — that lives under the bind-mounted `/Linux_for_Tegra`. This keeps the image small and the BSP version a runtime decision.

- [ ] **Step 1: Write the Containerfile**

```bash
cat >container/Containerfile <<'EOF'
# syntax=docker/dockerfile:1
FROM docker.io/library/ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Packages that l4t_flash_prerequisites.sh installs, plus tools the
# entrypoint uses. Pinned to the 22.04 archive at image-build time.
RUN apt-get update && apt-get install -y --no-install-recommends \
        qemu-user-static binfmt-support \
        libxml2 device-tree-compiler \
        python3 python3-yaml \
        abootimg sshpass dosfstools binutils cpio rsync zstd lbzip2 \
        uuid-runtime ca-certificates curl iproute2 \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /Linux_for_Tegra
ENTRYPOINT ["/entrypoint.sh"]
EOF
```

- [ ] **Step 2: Write the in-container entrypoint**

```bash
cat >container/entrypoint.sh <<'EOF'
#!/usr/bin/env bash
# Runs inside the jetson-restore container.
# Args: <board_id> <storage>
# Working directory: /Linux_for_Tegra (bind-mounted from host).
set -euo pipefail

BOARD_ID="${1:?board_id required (e.g., jetson-orin-nano-devkit)}"
STORAGE="${2:?storage required (e.g., nvme)}"

cd /Linux_for_Tegra

# apply_binaries.sh is one-time per BSP version. Mark with a dotfile so
# repeat runs skip it.
APPLIED_MARKER=".jr-binaries-applied"
if [[ ! -f "${APPLIED_MARKER}" ]]; then
    echo "[container] running apply_binaries.sh (one-time per BSP)…"
    ./tools/l4t_flash_prerequisites.sh
    ./apply_binaries.sh
    : > "${APPLIED_MARKER}"
else
    echo "[container] BSP binaries already applied"
fi

case "${STORAGE}" in
    nvme)
        external_device="nvme0n1p1"
        ;;
    *)
        echo "[container] unsupported storage: ${STORAGE}" >&2
        exit 2
        ;;
esac

echo "[container] running l4t_initrd_flash.sh for ${BOARD_ID} on ${STORAGE}"
exec ./tools/kernel_flash/l4t_initrd_flash.sh \
    --external-device "${external_device}" \
    -c ./tools/kernel_flash/flash_l4t_external.xml \
    --showlogs --network usb0 \
    "${BOARD_ID}" external
EOF
chmod +x container/entrypoint.sh
```

- [ ] **Step 3: Write a smoke test that asserts the entrypoint script syntax-checks and the Containerfile is valid**

```bash
cat >test/unit/container_smoke.bats <<'EOF'
#!/usr/bin/env bats

load ../helpers/load

@test "container/entrypoint.sh passes bash -n" {
    bash -n "${JR_REPO_ROOT}/container/entrypoint.sh"
}

@test "Containerfile has FROM ubuntu:22.04" {
    grep -E '^FROM\s+docker\.io/library/ubuntu:22\.04$' \
        "${JR_REPO_ROOT}/container/Containerfile"
}
EOF
```

- [ ] **Step 4: Run unit tests**

```bash
bats test/unit/container_smoke.bats
```

Expected: `2 tests, 0 failures`.

- [ ] **Step 5: Build the container locally to verify it builds clean**

```bash
make container
```

Expected: build completes; image tagged `jetson-restore:dev`.

- [ ] **Step 6: Smoke-run the container**

```bash
podman run --rm jetson-restore:dev --help 2>&1 | head -20
```

Expected: a usage message from `l4t_initrd_flash.sh` *or* an error referencing missing `/Linux_for_Tegra` content (the container exits because the BSP isn't bind-mounted in this smoke test) — either is acceptable; we're confirming the image runs.

- [ ] **Step 7: Lint and commit**

```bash
make lint
git add container/ test/unit/container_smoke.bats
git commit -m "feat(container): add Containerfile and entrypoint.sh"
```

---

## Phase 7: Flash orchestration

### Task 17: lib/flash.sh — assemble container invocation

**Files:**
- Create: `lib/flash.sh`
- Create: `test/unit/flash.bats`

- [ ] **Step 1: Write the failing test**

```bash
cat >test/unit/flash.bats <<'EOF'
#!/usr/bin/env bats

load ../helpers/load

setup() {
    for f in util config runtime flash; do
        # shellcheck source=/dev/null
        source "${JR_REPO_ROOT}/lib/${f}.sh"
    done
    jr_use_stub podman
    load_target  "${JR_REPO_ROOT}" "orin-nano-devkit"
    load_jetpack "${JR_REPO_ROOT}" "6.2.1"
    JR_WORKDIR="${JR_TMPDIR}/work"
    mkdir -p "${JR_WORKDIR}/Linux_for_Tegra"
    export JR_WORKDIR
}

@test "do_flash invokes podman with the expected argv" {
    do_flash
    jr_read_stub_log
    [[ "${output}" == *podman\ run\ --rm\ --privileged* ]]
    [[ "${output}" == *--net\ host* ]]
    [[ "${output}" == */dev/bus/usb:/dev/bus/usb* ]]
    [[ "${output}" == *Linux_for_Tegra:/Linux_for_Tegra* ]]
    [[ "${output}" == *jetson-orin-nano-devkit\ nvme* ]]
}

@test "do_flash uses the JR_CONTAINER_TAG from the jetpack config" {
    JR_CONTAINER_TAG="6.2.1"
    do_flash
    jr_read_stub_log
    [[ "${output}" == *:6.2.1* ]]
}
EOF
```

- [ ] **Step 2: Run, see fail**

```bash
bats test/unit/flash.bats
```

- [ ] **Step 3: Implement `lib/flash.sh`**

```bash
cat >lib/flash.sh <<'EOF'
#!/usr/bin/env bash
# Assemble and run the container.
set -euo pipefail

: "${JR_IMAGE:=ghcr.io/cbrake/jetson-restore}"
: "${JR_STORAGE:=nvme}"

do_flash() {
    local runtime
    runtime="$(detect_runtime)"
    local image="${JR_IMAGE}:${JR_CONTAINER_TAG}"

    log_info "running container ${image}"
    "${runtime}" run --rm \
        --privileged \
        --net host \
        -v /dev/bus/usb:/dev/bus/usb \
        -v "${JR_WORKDIR}/Linux_for_Tegra:/Linux_for_Tegra" \
        "${image}" \
        "${JR_BOARD_ID}" "${JR_STORAGE}"
}
EOF
```

- [ ] **Step 4: Run, see pass**

```bash
bats test/unit/flash.bats
```

Expected: `2 tests, 0 failures`.

- [ ] **Step 5: Lint and commit**

```bash
make lint
git add lib/flash.sh test/unit/flash.bats
git commit -m "feat(lib): add flash.sh container invocation"
```

---

### Task 18: lib/uninstall.sh — reverse everything preflight installed

**Files:**
- Create: `lib/uninstall.sh`
- Create: `test/unit/uninstall.bats`

- [ ] **Step 1: Write the failing test**

```bash
cat >test/unit/uninstall.bats <<'EOF'
#!/usr/bin/env bats

load ../helpers/load

setup() {
    for f in util udev netmgr nfs uninstall; do
        # shellcheck source=/dev/null
        source "${JR_REPO_ROOT}/lib/${f}.sh"
    done
    JR_UDEV_DEST="${JR_TMPDIR}/etc/udev/rules.d/70-jetson-restore.rules"
    JR_NM_DEST="${JR_TMPDIR}/etc/NetworkManager/system-connections/jetson-restore-rndis.nmconnection"
    JR_NFS_EXPORTS_DEST="${JR_TMPDIR}/etc/exports.d/jetson-restore.conf"
    JR_NFS_STATE_DIR="${JR_TMPDIR}/var/lib/jetson-restore"
    export JR_UDEV_DEST JR_NM_DEST JR_NFS_EXPORTS_DEST JR_NFS_STATE_DIR
    mkdir -p "$(dirname "${JR_UDEV_DEST}")" \
             "$(dirname "${JR_NM_DEST}")" \
             "$(dirname "${JR_NFS_EXPORTS_DEST}")" \
             "${JR_NFS_STATE_DIR}"
    jr_use_stub sudo
    jr_use_stub tee
    jr_use_stub udevadm
    jr_use_stub nmcli
    jr_use_stub exportfs
    jr_use_stub systemctl
}

@test "do_uninstall removes udev, NM, exports, and stops nfs only if we started it" {
    : > "${JR_UDEV_DEST}"
    : > "${JR_NM_DEST}"
    : > "${JR_NFS_EXPORTS_DEST}"
    : > "${JR_NFS_STATE_DIR}/nfs-server-started-by-us"

    do_uninstall

    [ ! -f "${JR_UDEV_DEST}" ]
    [ ! -f "${JR_NM_DEST}" ]
    [ ! -f "${JR_NFS_EXPORTS_DEST}" ]

    jr_read_stub_log
    [[ "${output}" == *systemctl\ stop\ nfs-server* ]]
}

@test "do_uninstall does not stop nfs-server when no marker is present" {
    do_uninstall
    jr_read_stub_log
    [[ "${output}" != *systemctl\ stop\ nfs-server* ]]
}
EOF
```

- [ ] **Step 2: Run, see fail**

```bash
bats test/unit/uninstall.bats
```

- [ ] **Step 3: Implement `lib/uninstall.sh`**

```bash
cat >lib/uninstall.sh <<'EOF'
#!/usr/bin/env bash
# Reverse everything preflight installed.
set -euo pipefail

do_uninstall() {
    log_info "uninstalling jetson-restore host config"
    remove_udev_rule
    remove_nm_keyfile
    remove_nfs_export
    stop_nfs_server_if_we_started_it
    log_info "done; cached BSP under ./work/cache/ is intact"
}
EOF
```

- [ ] **Step 4: Run, see pass**

```bash
bats test/unit/uninstall.bats
```

Expected: `2 tests, 0 failures`.

- [ ] **Step 5: Lint and commit**

```bash
make lint
git add lib/uninstall.sh test/unit/uninstall.bats
git commit -m "feat(lib): add uninstall.sh"
```

---

## Phase 8: CLI entrypoint

### Task 19: bin/jetson-restore — argument parsing and dispatch

**Files:**
- Create: `bin/jetson-restore`
- Create: `test/unit/cli.bats`

- [ ] **Step 1: Write the failing test**

```bash
cat >test/unit/cli.bats <<'EOF'
#!/usr/bin/env bats

load ../helpers/load

@test "jetson-restore --help prints usage and exits 0" {
    run "${JR_REPO_ROOT}/bin/jetson-restore" --help
    assert_success
    [[ "${output}" == *Usage* ]]
    [[ "${output}" == *--target* ]]
    [[ "${output}" == *uninstall* ]]
}

@test "jetson-restore with no args prints usage and exits 2" {
    run "${JR_REPO_ROOT}/bin/jetson-restore"
    assert_failure 2
    [[ "${output}" == *Usage* ]]
}

@test "jetson-restore --target unknown errors clearly" {
    run "${JR_REPO_ROOT}/bin/jetson-restore" --target unknown-target
    assert_failure 2
    [[ "${output}" == *unknown\ target* ]]
}

@test "jetson-restore --dry-run prints commands without executing them" {
    run "${JR_REPO_ROOT}/bin/jetson-restore" \
        --target orin-nano-devkit --dry-run
    # Should mention the runtime command it would have run.
    [[ "${output}" == *DRY-RUN* ]]
}
EOF
```

- [ ] **Step 2: Run, see fail**

```bash
bats test/unit/cli.bats
```

- [ ] **Step 3: Implement `bin/jetson-restore`**

```bash
mkdir -p bin
cat >bin/jetson-restore <<'EOF'
#!/usr/bin/env bash
# jetson-restore — restore stock NVIDIA L4T Ubuntu onto Jetson Orin dev kits.
set -euo pipefail

# Resolve the repo root from this script's location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JR_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export JR_REPO_ROOT

# Source libs in dependency order.
for f in util config runtime recovery udev netmgr nfs cache preflight flash uninstall; do
    # shellcheck source=/dev/null
    source "${JR_REPO_ROOT}/lib/${f}.sh"
done

usage() {
    cat <<USAGE
Usage:
  jetson-restore --target <name> [--storage nvme] [--jetpack <ver>]
                 [--dry-run] [--check] [--skip-preflight]
                 [--no-sudo] [--start-services]
                 [--keep-work] [--device <bus>:<dev>]

  jetson-restore uninstall

Targets:
$(list_targets "${JR_REPO_ROOT}" | sed 's/^/  /')

Examples:
  jetson-restore --target orin-nano-devkit
  jetson-restore --target agx-orin-devkit --jetpack 6.2.1
  jetson-restore --check    # preflight only, no flash
  jetson-restore uninstall  # remove host config
USAGE
}

if [[ $# -eq 0 ]]; then
    usage
    exit 2
fi

# Subcommand: uninstall.
if [[ "$1" == "uninstall" ]]; then
    do_uninstall
    exit 0
fi

# Defaults.
JR_TARGET=""
JR_STORAGE="nvme"
JR_JETPACK_OVERRIDE=""
JR_DRY_RUN=0
JR_CHECK_ONLY=0
JR_SKIP_PREFLIGHT=0
JR_NO_SUDO=0
JR_START_SERVICES=0
JR_KEEP_WORK=0
JR_DEVICE=""
export JR_DRY_RUN JR_NO_SUDO

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)          JR_TARGET="$2"; shift 2;;
        --storage)         JR_STORAGE="$2"; shift 2;;
        --jetpack)         JR_JETPACK_OVERRIDE="$2"; shift 2;;
        --dry-run)         JR_DRY_RUN=1; shift;;
        --check)           JR_CHECK_ONLY=1; shift;;
        --skip-preflight)  JR_SKIP_PREFLIGHT=1; shift;;
        --no-sudo)         JR_NO_SUDO=1; shift;;
        --start-services)  JR_START_SERVICES=1; shift;;
        --keep-work)       JR_KEEP_WORK=1; shift;;
        --device)          JR_DEVICE="$2"; shift 2;;
        --help|-h)         usage; exit 0;;
        *)                 log_die "unknown argument: $1";;
    esac
done

if [[ -z "${JR_TARGET}" ]]; then
    log_err "missing --target"
    usage
    exit 2
fi
if [[ "${JR_STORAGE}" != "nvme" ]]; then
    log_die "unsupported storage in v1: ${JR_STORAGE} (only nvme)"
fi

load_target  "${JR_REPO_ROOT}" "${JR_TARGET}"
load_jetpack "${JR_REPO_ROOT}" "${JR_JETPACK_OVERRIDE:-${JR_DEFAULT_JETPACK}}"

# Workdir is ./work next to bin/.
JR_WORKDIR="${JR_REPO_ROOT}/work"
mkdir -p "${JR_WORKDIR}"
export JR_WORKDIR JR_STORAGE JR_DEVICE

# Sudo queue file used in --no-sudo mode.
if [[ "${JR_NO_SUDO}" == "1" ]]; then
    JR_SUDO_QUEUE_FILE="${JR_WORKDIR}/preflight.sh"
    : >"${JR_SUDO_QUEUE_FILE}"
    chmod +x "${JR_SUDO_QUEUE_FILE}"
    export JR_SUDO_QUEUE_FILE
fi

if [[ "${JR_SKIP_PREFLIGHT}" != "1" ]]; then
    run_preflight
fi

if [[ "${JR_CHECK_ONLY}" == "1" ]]; then
    log_info "preflight complete; exiting (--check)"
    exit 0
fi

ensure_l4t_extracted "${JR_WORKDIR}"
do_flash

log_info "flash complete; reboot the device to boot into Ubuntu"
EOF
chmod +x bin/jetson-restore
```

- [ ] **Step 4: Run, see pass**

```bash
bats test/unit/cli.bats
```

Expected: `4 tests, 0 failures`. Note: the `--dry-run` test will fail until we verify the chain runs through — if it fails, debug by setting `set -x` in the entrypoint and re-running. The most likely cause is a real `lsusb`/`nfs` etc. running because the test didn't activate stubs. Resolve by extending `cli.bats` to load stubs into PATH before invoking the entrypoint, or by short-circuiting `--dry-run` to skip preflight entirely. Keeping it simple: have the entrypoint short-circuit `--dry-run` to print the would-run commands and exit, rather than actually walking preflight. Replace the bottom of the entrypoint:

```bash
sed -i 's/^if \[\[ "${JR_SKIP_PREFLIGHT}" != "1" \]\]; then/if [[ "${JR_DRY_RUN}" == "1" ]]; then\n    log_info "[DRY-RUN] would run preflight, then ensure_l4t_extracted, then flash for ${JR_BOARD_ID} on ${JR_STORAGE}"\n    exit 0\nfi\n\nif [[ "${JR_SKIP_PREFLIGHT}" != "1" ]]; then/' bin/jetson-restore
```

(Or do the edit by hand — the goal is: when `--dry-run` is set, after argument parsing and config loading, log a single dry-run summary and exit 0.)

Re-run:

```bash
bats test/unit/cli.bats
```

Expected: `4 tests, 0 failures`.

- [ ] **Step 5: Lint and commit**

```bash
make lint
git add bin/jetson-restore test/unit/cli.bats
git commit -m "feat(bin): add jetson-restore CLI entrypoint with subcommands"
```

---

## Phase 9: Reproducibility test

### Task 20: Reproducibility — assembled argv is deterministic

**Files:**
- Create: `test/unit/repro.bats`
- Create: `test/fixtures/expected-orin-nano-argv.txt`
- Create: `test/fixtures/expected-orin-nano-exports.txt`

The reproducibility test pins the *exact* container argv and exports.d snippet for a given `--target` + `--jetpack`. If a refactor changes one accidentally, this test catches it.

- [ ] **Step 1: Generate the expected fixtures**

```bash
mkdir -p test/fixtures
JR_REPO_ROOT="$(pwd)"
source lib/util.sh
source lib/config.sh
source lib/runtime.sh
load_target  "${JR_REPO_ROOT}" "orin-nano-devkit"
load_jetpack "${JR_REPO_ROOT}" "6.2.1"

# Expected container argv (host-portable: drop the absolute workdir prefix).
cat >test/fixtures/expected-orin-nano-argv.txt <<EOF
podman run --rm --privileged --net host -v /dev/bus/usb:/dev/bus/usb -v <WORKDIR>/Linux_for_Tegra:/Linux_for_Tegra ghcr.io/cbrake/jetson-restore:6.2.1 jetson-orin-nano-devkit nvme
EOF

# Expected exports.d snippet (after rendering with WORKDIR placeholder).
cat >test/fixtures/expected-orin-nano-exports.txt <<EOF
<WORKDIR>/Linux_for_Tegra 192.168.55.0/24(rw,sync,no_subtree_check,no_root_squash)
EOF
```

- [ ] **Step 2: Write the bats test**

```bash
cat >test/unit/repro.bats <<'EOF'
#!/usr/bin/env bats

load ../helpers/load

setup() {
    for f in util config runtime flash; do
        # shellcheck source=/dev/null
        source "${JR_REPO_ROOT}/lib/${f}.sh"
    done
    jr_use_stub podman
    load_target  "${JR_REPO_ROOT}" "orin-nano-devkit"
    load_jetpack "${JR_REPO_ROOT}" "6.2.1"
    JR_WORKDIR="${JR_TMPDIR}/work"
    mkdir -p "${JR_WORKDIR}/Linux_for_Tegra"
    export JR_WORKDIR
}

@test "container argv matches the pinned expected-orin-nano-argv.txt" {
    do_flash
    jr_read_stub_log
    actual="$(printf '%s' "${output}" | sed "s|${JR_WORKDIR}|<WORKDIR>|g")"
    expected="$(cat "${JR_REPO_ROOT}/test/fixtures/expected-orin-nano-argv.txt")"
    assert_equal "${actual}" "${expected}"
}

@test "exports snippet for orin-nano matches expected-orin-nano-exports.txt" {
    rendered="$(sed "s|@JR_EXPORT_PATH@|${JR_WORKDIR}/Linux_for_Tegra|g" \
                    "${JR_REPO_ROOT}/share/jetson-restore.exports.tmpl")"
    actual="$(printf '%s' "${rendered}" | sed "s|${JR_WORKDIR}|<WORKDIR>|g")"
    expected="$(cat "${JR_REPO_ROOT}/test/fixtures/expected-orin-nano-exports.txt")"
    assert_equal "${actual}" "${expected}"
}
EOF
```

- [ ] **Step 3: Run, see pass**

```bash
bats test/unit/repro.bats
```

Expected: `2 tests, 0 failures`.

- [ ] **Step 4: Commit**

```bash
git add test/unit/repro.bats test/fixtures/
git commit -m "test: add reproducibility check on argv and exports snippet"
```

---

## Phase 10: Container build CI

### Task 21: CI — build the container in a separate job

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add a `container-build` job**

Append to `.github/workflows/ci.yml`:

```yaml
  container-build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build container
        run: podman build -t jetson-restore:ci -f container/Containerfile container/
      - name: Smoke-run container
        run: |
          # The entrypoint requires args; assert it errors with our message.
          set +e
          out="$(podman run --rm jetson-restore:ci 2>&1)"
          rc=$?
          set -e
          if [[ ${rc} -eq 0 ]]; then
            echo "expected nonzero exit when no args"; exit 1
          fi
          [[ "${out}" == *board_id\ required* ]] || { echo "${out}"; exit 1; }
```

- [ ] **Step 2: Push and verify CI passes**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add container-build job"
git push  # only if a remote is configured
```

If running locally, simulate the job:

```bash
podman build -t jetson-restore:ci -f container/Containerfile container/
podman run --rm jetson-restore:ci 2>&1 | head -20  # expect a usage/error message
```

- [ ] **Step 3: Commit (if not already)**

```bash
# already committed in step 1
```

---

## Phase 11: Release workflow

### Task 22: GitHub Actions release workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Write the release workflow**

```bash
cat >.github/workflows/release.yml <<'EOF'
name: release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write
  packages: write

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Read JetPack version from jetpacks/6.2.1.conf
        id: jp
        run: |
          # Single-version pin in v1: 6.2.1.
          echo "version=6.2.1" >>"${GITHUB_OUTPUT}"

      - name: Log into ghcr.io
        run: echo "${{ secrets.GITHUB_TOKEN }}" | \
               podman login ghcr.io -u "${{ github.actor }}" --password-stdin

      - name: Build container
        run: |
          podman build \
            -t "ghcr.io/${{ github.repository_owner }}/jetson-restore:${{ github.ref_name }}" \
            -t "ghcr.io/${{ github.repository_owner }}/jetson-restore:${{ steps.jp.outputs.version }}" \
            -f container/Containerfile container/

      - name: Push container
        run: |
          podman push "ghcr.io/${{ github.repository_owner }}/jetson-restore:${{ github.ref_name }}"
          podman push "ghcr.io/${{ github.repository_owner }}/jetson-restore:${{ steps.jp.outputs.version }}"

      - name: Create release
        uses: softprops/action-gh-release@v2
        with:
          generate_release_notes: true
          fail_on_unmatched_files: true
          files: |
            CHANGELOG.md
EOF
```

- [ ] **Step 2: Create a stub CHANGELOG**

```bash
cat >CHANGELOG.md <<'EOF'
# Changelog

## Unreleased
- Initial release: Orin Nano dev kit, AGX Orin dev kit, NVMe, JetPack 6.2.1.
EOF
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml CHANGELOG.md
git commit -m "ci: add release workflow that publishes to ghcr.io"
```

---

## Phase 12: Documentation

### Task 23: README, ARCHITECTURE, TROUBLESHOOTING

**Files:**
- Modify: `docs/README.md` (replace placeholder with full content)
- Create: `docs/ARCHITECTURE.md`
- Create: `docs/TROUBLESHOOTING.md`

- [ ] **Step 1: Write the full README**

```markdown
# jetson-restore

Restore stock NVIDIA L4T Ubuntu onto Jetson Orin dev kits from any modern Linux host. One command, scriptable, idempotent.

## Supported targets (v1)

- Orin Nano dev kit (NVMe)
- AGX Orin dev kit (NVMe)
- JetPack 6.2.1 / L4T R36.4.4

## Quick start

1. Install dependencies:

   - Arch: `sudo pacman -S podman nfs-utils sudo`
   - Ubuntu: `sudo apt install podman nfs-kernel-server sudo`

2. Plug the dev kit into this host via USB-C and put it in recovery mode (see TROUBLESHOOTING.md if you're not sure how).

3. Run:

   ```bash
   git clone https://github.com/<owner>/jetson-restore
   cd jetson-restore
   ./bin/jetson-restore --target orin-nano-devkit
   ```

4. Wait. The first run downloads ~8 GB of BSP and rootfs into `./work/cache/`. Subsequent runs are fast.

5. When the script reports "flash complete", reboot the device. It boots into stock L4T Ubuntu 22.04.

## Other commands

- `jetson-restore --check` — preflight only, no flash.
- `jetson-restore --dry-run` — print every command that would run.
- `jetson-restore --no-sudo` — write sudo commands to `./work/preflight.sh` for manual execution.
- `jetson-restore uninstall` — remove the udev rule, NM keyfile, NFS export, and stop nfs-server iff jetson-restore started it.

## What it changes on your host

Persistent (idempotent) — left in place across runs:

- `/etc/udev/rules.d/70-jetson-restore.rules` — non-root access to VID `0955` and USB autosuspend disable.
- `/etc/NetworkManager/system-connections/jetson-restore-rndis.nmconnection` — ignore the recovery RNDIS interface.
- `/etc/exports.d/jetson-restore.conf` — NFS export of `./work/Linux_for_Tegra` to `192.168.55.0/24` only.
- `nfs-server` started and enabled (idle daemon listening on port 2049).

Run `jetson-restore uninstall` to remove all of the above.

## License

Apache-2.0.
```

- [ ] **Step 2: Write ARCHITECTURE.md (point at the design spec, summarize for readers)**

```bash
cat >docs/ARCHITECTURE.md <<'EOF'
# Architecture

This file is a contributor-facing summary. The full design spec is in
[superpowers/specs/2026-04-27-jetson-restore-design.md](superpowers/specs/2026-04-27-jetson-restore-design.md).

## Two-layer design

- **Host wrapper (bash)** — preflight, NFS export, container orchestration.
- **Container (Ubuntu 22.04)** — NVIDIA's BSP toolchain, runs `l4t_initrd_flash.sh`.

The two share a bind-mounted `./work/` directory. The host NFS server exports
`./work/Linux_for_Tegra` to the recovery RNDIS subnet (`192.168.55.0/24`).
The Jetson's initrd, booted over USB, mounts that export to fetch the rootfs.

## Why not flash directly from Arch?

NVIDIA's `apply_binaries.sh` and friends assume Debian-isms (`dpkg`,
`start-stop-daemon`, exact qemu-user-static paths). Patching them is ongoing
maintenance. Containerizing the BSP toolchain pins those assumptions to a
known Ubuntu 22.04 layer and lets the host be anything.

## Why NFS, not just bind-mount?

JetPack 6 flashes via an initrd that boots on the device, brings up RNDIS over
USB, and mounts the rootfs from the host. The host has to expose the rootfs
over NFS for that mount to work. Bind-mounting works for the BSP scripts on
the host side but doesn't help the device — only NFS does.

## Adding a new target

Drop a file in `targets/<name>.conf` with the keys the existing files use
(see `targets/orin-nano-devkit.conf` for the canonical example). No code
change required.

## Adding a new JetPack version

Drop a file in `jetpacks/<version>.conf`. Build and push a new container
image tagged `:<version>`. Update `jetpacks/<version>.conf`'s
`JR_CONTAINER_TAG`.
EOF
```

- [ ] **Step 3: Write TROUBLESHOOTING.md**

```bash
cat >docs/TROUBLESHOOTING.md <<'EOF'
# Troubleshooting

## "device not in recovery mode"

You forgot the recovery button combo, or the cable is data-only.

- **Orin Nano dev kit:** jumper pins 9–10 (FC REC + GND) on J14, then power on.
- **AGX Orin dev kit:** hold FORCE RECOVERY, press POWER, release after ~2 s.

Verify with `lsusb | grep 0955`.

## "another route exists for 192.168.55.0/24"

Something on your host is already using the RNDIS subnet — typically a VPN,
VirtualBox, or a Docker bridge. Either bring it down for the duration of the
flash, or change its subnet.

## Flash hangs at "Sending bootloader"

USB autosuspend is the usual cause. The udev rule disables it for VID 0955,
but if you're on a host where udev rules don't apply (some immutable distros),
disable it globally for the flash:

    echo -1 | sudo tee /sys/module/usbcore/parameters/autosuspend

## "nfs-server: Failed to start"

Some distros split NFS into multiple services. Try:

    sudo systemctl start nfs-kernel-server     # Ubuntu/Debian
    sudo systemctl start nfs-server.service    # Arch/RHEL

If both fail, install nfs-utils (Arch) or nfs-kernel-server (Ubuntu) and re-run.

## "checksum mismatch" on BSP download

NVIDIA occasionally rebuilds tarballs without changing the URL. If you trust
the source, update the SHA-256 in `jetpacks/<version>.conf` to match
`sha256sum` of the freshly downloaded file. Open an issue with the new value
so we can update the pinned config.
EOF
```

- [ ] **Step 4: Replace the placeholder docs/README.md with the full version (Step 1 above)**

```bash
# Write the full README content from Step 1 to docs/README.md.
# (The author should paste the markdown block from Step 1.)
```

- [ ] **Step 5: Commit**

```bash
git add docs/README.md docs/ARCHITECTURE.md docs/TROUBLESHOOTING.md
git commit -m "docs: add README, ARCHITECTURE, TROUBLESHOOTING"
```

---

## Phase 13: End-to-end test harness (gated)

### Task 24: test/e2e/orin-nano.sh — manual hardware verification

**Files:**
- Create: `test/e2e/README.md`
- Create: `test/e2e/orin-nano.sh`
- Create: `test/e2e/agx-orin.sh`

These tests require physical hardware. They run only when `JETSON_RESTORE_E2E=1` is set, and they're invoked manually before tagging a release.

- [ ] **Step 1: Write the e2e README**

```bash
cat >test/e2e/README.md <<'EOF'
# End-to-end tests

These tests run a full flash against a real device and verify the result.
They are NOT run in CI — they need hardware and take ~30 minutes each.

To run:

    JETSON_RESTORE_E2E=1 ./test/e2e/orin-nano.sh
    JETSON_RESTORE_E2E=1 ./test/e2e/agx-orin.sh

Expected output: PASS, with the captured `cat /etc/nv_tegra_release` from the
device matching the expected JetPack version.

Run before tagging a release. Paste the log into the GitHub Release notes.
EOF
```

- [ ] **Step 2: Write the orin-nano e2e script**

```bash
cat >test/e2e/orin-nano.sh <<'EOF'
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
EOF
chmod +x test/e2e/orin-nano.sh
```

- [ ] **Step 3: Write the agx-orin e2e script (analogous)**

```bash
cat >test/e2e/agx-orin.sh <<'EOF'
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
EOF
chmod +x test/e2e/agx-orin.sh
```

- [ ] **Step 4: Commit**

```bash
git add test/e2e/
git commit -m "test(e2e): add manual hardware verification scripts (gated)"
```

---

## Phase 14: Cross-task verification

### Task 25: Run the full test suite, lint, and a real container build

**Files:** none modified.

- [ ] **Step 1: Run the whole local pipeline**

```bash
make lint
make test
make container
```

Expected:
- `make lint`: exit 0, no shellcheck or shfmt diffs.
- `make test`: every bats file passes; total tests in the 30+ range.
- `make container`: builds a fresh image without errors.

- [ ] **Step 2: Bump CHANGELOG and tag**

When the maintainer is satisfied:

```bash
# Manually edit CHANGELOG.md to move "Unreleased" entries under v0.1.0.
git add CHANGELOG.md
git commit -m "release: v0.1.0"
git tag -a v0.1.0 -m "v0.1.0: initial Orin Nano + AGX Orin support, JetPack 6.2.1"
```

(Push only when ready: `git push && git push --tags`. The release workflow takes over from there.)

- [ ] **Step 3: Run the E2E suite locally before publishing the release**

```bash
JETSON_RESTORE_E2E=1 ./test/e2e/orin-nano.sh   # with Orin Nano plugged in
JETSON_RESTORE_E2E=1 ./test/e2e/agx-orin.sh    # with AGX Orin plugged in
```

Paste the PASS lines into the auto-drafted GitHub Release notes, then publish.

---

## Self-review

**Spec coverage**

- §1 Problem → Tasks 1–25 exist; the tool produces the artifacts described.
- §2 Goals → Single-command flash (Task 19), idempotent host setup (Tasks 11–13), reproducibility (Task 20), distributable container (Tasks 16, 21, 22).
- §3 Scope (Orin Nano + AGX Orin, NVMe, stock L4T, JetPack 6.2.1) → Tasks 4, 5, 16.
- §4 Architecture (two-layer; bind-mounted ./work/) → Tasks 16, 17, 19.
- §4.1 CLI surface → Task 19.
- §4.2 Implementation choices (bash, podman/docker, JetPack pinning, ghcr.io) → Tasks 7, 9, 5, 22.
- §5 Components → Tasks 7–18 cover the lib/, share/, container/, and bin/ files; Task 1 sets up `Makefile` and lint configs.
- §6 Preflight 12 checks → Task 15 (preflight.sh) plus the building blocks in Tasks 11–14.
- §7 Data flow → mirrored in `bin/jetson-restore` (Task 19) and `entrypoint.sh` (Task 16).
- §8 Error handling → `log_die` discipline in Task 7, propagation in Tasks 17 and 19.
- §9 Testing strategy → bats unit tests throughout, container build job (Task 21), reproducibility (Task 20), uninstall (Task 18), CI workflows (Tasks 3, 21), gated E2E (Task 24).
- §10 Prior art → covered in spec; no plan tasks needed.

**Placeholder scan**

- `jetpacks/6.2.1.conf` contains `REPLACE_AT_IMPLEMENTATION_TIME` for the SHA-256s. This is intentional and tested-against (Task 5 fails until it's filled in). Documented as an implementer action item.
- `JR_IMAGE` defaults to `ghcr.io/cbrake/jetson-restore` in `lib/flash.sh`; the maintainer should change this to the actual GitHub owner before tagging v0.1.0. Adding a one-line note in CHANGELOG to remind.
- No "TBD"/"TODO"/"add appropriate error handling" patterns elsewhere.

**Type / name consistency**

- `do_flash`, `do_uninstall`, `run_preflight` — verb names match across tasks.
- `JR_*` env vars: target conf provides `JR_BOARD_ID`, `JR_USB_PRODUCT_ID`, `JR_DEFAULT_JETPACK`, `JR_DEFAULT_STORAGE`, `JR_RECOVERY_INSTRUCTIONS`. JetPack conf provides `JR_JETPACK_VERSION`, `JR_L4T_VERSION`, `JR_BSP_*`, `JR_ROOTFS_*`, `JR_CONTAINER_TAG`. Both used consistently in `bin/jetson-restore` and `lib/flash.sh`.
- `install_*`/`remove_*` pairs match: `install_udev_rule` ↔ `remove_udev_rule`, `install_nm_keyfile` ↔ `remove_nm_keyfile`, `install_nfs_export` ↔ `remove_nfs_export`, `ensure_nfs_server_running` ↔ `stop_nfs_server_if_we_started_it`.
- `JR_FS_WRITER` indirection used identically in `lib/udev.sh`, `lib/netmgr.sh`, `lib/nfs.sh`.

No issues found that require revision.
