# jetson-restore — Design

**Status:** Approved (sections 1–3, 2026-04-27) **Scope:** v1 **Audience:** Yoe
/ Jetson community; users on Arch Linux (and any modern Linux) who need a clean,
scriptable way to restore stock NVIDIA L4T Ubuntu onto Jetson Orin dev kits.

## 1. Problem

NVIDIA's official flashing toolchain assumes an Ubuntu 20.04/22.04 host. Users
on Arch (or NixOS, Fedora, etc.) currently choose between:

- Running the official **SDK Manager Docker image** — works but is
  interactive-leaning, ~2 GB of tooling, requires a devzone login, and is poorly
  suited to scripted/automated reflashing.
- Following community recipes (the SamueleFacenda NixOS gist, the bensyz Arch
  blog) — work, but are unpackaged shell snippets with no tests, no versioning,
  no maintenance.
- Patching NVIDIA's scripts to run natively on Arch — works but is ongoing
  maintenance.

There is no maintained, distributable tool that turns "Arch host + Orin dev kit
in recovery mode" into a one-command, reproducible restore to stock L4T Ubuntu.

## 2. Goals & Non-goals

**Goals**

- Single command flashes a known Orin dev kit to a pinned, tested JetPack 6.x +
  stock NVIDIA Ubuntu rootfs.
- Works from Arch Linux today and from any Linux host where podman/docker +
  nfs-utils are available.
- Idempotent host setup — running it twice is fast and safe.
- Reproducible: same `--target` + `--jetpack` produces the same flash command
  and same artifacts every time.
- Distributable: container image on `ghcr.io`, source on GitHub, optional AUR
  package later.

**Non-goals (v1)**

- Yoe / Yocto images. (Repo name is `jetson-restore`; "restore" means stock
  L4T.)
- Third-party carrier boards (Seeed, Antmicro, Connect Tech). Pluggable later
  via `targets/`.
- Orin NX modules.
- SD-card flow (older Orin Nano) and JetPack 5.x.
- A GUI / TUI.
- A configuration / manifest file format for batch flashing many boards.

## 3. Scope (v1)

| Dimension         | v1 coverage                                                                                              |
| ----------------- | -------------------------------------------------------------------------------------------------------- |
| Targets           | Orin Nano dev kit, AGX Orin dev kit                                                                      |
| Storage           | NVMe                                                                                                     |
| OS image          | Stock NVIDIA L4T Ubuntu 22.04, the sample rootfs NVIDIA ships per JetPack version                        |
| JetPack           | One pinned version per release of the tool (initial pin: 6.2.1, L4T R36.4.4); `--jetpack` flag overrides |
| Host distros      | Arch Linux primary; any Linux with podman/docker + nfs-utils + systemd should work                       |
| Container runtime | podman preferred, docker supported                                                                       |

## 4. Architecture

Two-layer design: a thin host-side wrapper plus an Ubuntu container that carries
NVIDIA's BSP toolchain.

```
┌─────────────────────────────────────────────────────────────┐
│  jetson-restore (host, Arch or any Linux)                   │
│  ────────────────────────────────────────                   │
│  • CLI entrypoint (bash)                                    │
│  • Preflight: USB autosuspend, udev rule, RNDIS, NM ignore  │
│  • Starts host NFS export of a real dir under ./work/       │
│  • Runs container (podman/docker, --privileged,             │
│    -v /dev/bus/usb:/dev/bus/usb)                            │
└────────────────────┬────────────────────────────────────────┘
                     │ bind-mount ./work/ into container
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  jetson-restore container (ghcr.io/.../jetson-restore)      │
│  ────────────────────────────────────────────────────       │
│  Ubuntu 22.04, pinned                                       │
│  • qemu-user-static + binfmts for aarch64 chroot            │
│  • JetPack 6.x BSP (downloaded into ./work/ at first run)   │
│  • Sample rootfs tarball (downloaded into ./work/)          │
│  • Invokes l4t_initrd_flash.sh with per-model config        │
└─────────────────────────────────────────────────────────────┘
```

**Why this split**

- The container holds everything Ubuntu-specific — qemu-user-static binfmts,
  `apply_binaries.sh`, `l4t_initrd_flash.sh`, the Python/Debian-isms NVIDIA's
  BSP scripts assume. No patching of upstream scripts required.
- The host holds everything that must be real-host (NFS export of a non-overlay
  path; JetPack 6 initrd flash requires this) or that needs host capability
  (udev, NetworkManager, systemd).
- Container image is immutable and reproducible; per-run state lives in a
  bind-mounted `./work/` so downloads cache across runs.

**Critical constraint** — the path `./work/Linux_for_Tegra` on the host is what
gets bind-mounted into the container _and_ what NFS exports. Both layers see the
same real filesystem path. Docker overlay paths break NFS export-from-overlay;
this is the most common failure mode in community recipes and the architecture
must avoid it by construction.

### 4.1 CLI surface

```
jetson-restore [--target <name>] [--storage nvme] [--jetpack <ver>]
               [--dry-run] [--check] [--skip-preflight]
               [--no-sudo] [--start-services]
               [--keep-work] [--device <bus>:<port>]

# v1: --storage accepts only `nvme`. The flag exists for forward compatibility.

jetson-restore uninstall      # remove udev rule, NM keyfile, exports.d snippet
jetson-restore --check        # run preflight only, no flash
jetson-restore --dry-run      # print every command that would run; touch nothing
```

### 4.2 Implementation choices

| Choice            | Decision                                                           | Rationale                                                          |
| ----------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------ |
| Host language     | bash                                                               | Arch minimal deps; easy to audit; matches NVIDIA's own tooling     |
| Container runtime | podman preferred, docker supported                                 | Arch defaults to podman; CLI surfaces are compatible for our needs |
| JetPack pinning   | one tested version per tool release; overridable                   | Reproducibility                                                    |
| Distribution      | GitHub source + `ghcr.io` container image                          | Free, signed, CI-friendly. AUR package follow-up.                  |
| Privilege model   | explicit one-prompt sudo, or `--no-sudo` writes commands to a file | No quiet sudo magic                                                |

## 5. Components

```
jetson-restore/
├── bin/
│   └── jetson-restore               # entrypoint
├── lib/
│   ├── preflight.sh                 # all 12 host checks; idempotent
│   ├── nfs.sh                       # exports.d management
│   ├── udev.sh                      # rule install / verification
│   ├── netmgr.sh                    # NM + systemd-networkd RNDIS handling
│   ├── runtime.sh                   # podman/docker abstraction
│   ├── recovery.sh                  # device detection (lsusb, model ID)
│   ├── cache.sh                     # BSP / rootfs download + checksum
│   └── flash.sh                     # container invocation, arg assembly
├── targets/
│   ├── orin-nano-devkit.conf        # board id, storage, default JP, recovery instructions
│   └── agx-orin-devkit.conf
├── jetpacks/
│   └── 6.2.1.conf                   # BSP URL, rootfs URL, sha256, l4t_initrd_flash flags
├── container/
│   ├── Containerfile                # Ubuntu 22.04 + qemu-user-static + l4t_flash_prerequisites.sh
│   └── entrypoint.sh                # in-container: apply_binaries → l4t_initrd_flash.sh
├── share/
│   ├── 70-jetson-restore.rules      # udev template
│   ├── jetson-restore.nmconnection  # NM keyfile template
│   └── exports.d-template
├── test/
│   ├── preflight_test.bats
│   ├── targets_test.bats
│   └── e2e/                         # gated, requires hardware + JETSON_RESTORE_E2E=1
└── docs/
    ├── README.md
    ├── ARCHITECTURE.md
    └── TROUBLESHOOTING.md
```

**Layout rationale**

- One file per concern in `lib/`, ~100–200 lines each. Sourced individually so
  unit tests can stub one without dragging in the rest.
- `targets/*.conf` and `jetpacks/*.conf` are plain `KEY=value` shell files.
  Adding a new target = add a file, no code change. This is the seam for future
  Orin NX, third-party carriers, JetPack 7.
- `container/` is what gets built and pushed; tagged with both the tool version
  and the JetPack version it tracks (`:v0.1.0`, `:6.2.1`).
- `share/` holds templates the runtime fills in. Templates checked in; rendered
  files land under `./work/`.

## 6. Preflight

All preflight actions are **persistent and idempotent**. There is no post-flight
cleanup phase. Users who want to fully remove what jetson-restore added run
`jetson-restore uninstall`.

| #   | Check / action                                                     | Rationale                                                              |
| --- | ------------------------------------------------------------------ | ---------------------------------------------------------------------- |
| 1   | Container runtime present (podman or docker)                       | Can't run flash container without it                                   |
| 2   | Disk space in `./work/` ≥ 30 GB free                               | BSP + rootfs + generated images                                        |
| 3   | `nfs-utils` installed; `nfs-server` enabled & active               | JetPack 6 initrd flash mounts rootfs over NFS                          |
| 4   | NFS export of `./work/Linux_for_Tegra/` to `192.168.55.0/24`       | Initrd needs a real host path; subnet is the RNDIS link                |
| 5   | udev rule installed for VID `0955`                                 | Allow non-root access in recovery mode                                 |
| 6   | USB autosuspend disabled for VID `0955` (per-device udev)          | Prevent mid-flash device drop                                          |
| 7   | NetworkManager / systemd-networkd configured to ignore RNDIS MAC   | Prevent NM races on the recovery USB interface                         |
| 8   | No conflicting route on `192.168.55.0/24`                          | VPNs / VMs sometimes hijack this subnet                                |
| 9   | At most one VID `0955` device attached (or `--device` given)       | Avoid `tegrarcm_v2` confusion                                          |
| 10  | Device in recovery mode (`lsusb` shows `0955:7e19` or `0955:7023`) | Wait up to 30 s; print model-specific recovery instructions if missing |
| 11  | Container image present locally or pullable                        | Avoid surprise pull mid-flow                                           |
| 12  | BSP + rootfs cached or downloadable, checksums verified            | Avoid surprise 8 GB download mid-flow                                  |

**Honesty about nfs-server:** starting nfs-server leaves a network daemon
running on the host (listening on 2049 on all interfaces by default). The
_export_ is locked to RNDIS, so the served data isn't reachable elsewhere, but
the daemon itself is. v1 starts it, leaves it, and prints loudly that it did so,
with a one-line hint to `systemctl disable --now nfs-server` for users who'd
rather it be off. Binding nfs-server's listeners to `192.168.55.1` only is a
follow-up.

**Sudo policy:** the wrapper does not assume passwordless sudo. It prints
exactly which commands need elevation, in order, and either runs them with
`sudo` (one prompt per session) or — with `--no-sudo` — writes them to
`./work/preflight.sh` for the user to run manually. No silent sudo.

**`--check`** runs preflight only, exits with the list of things that would
change. Cheap pre-flight debug.

## 7. Data flow (a single flash)

```
user runs: jetson-restore --target orin-nano-devkit --storage nvme

  1. parse args, load targets/orin-nano-devkit.conf + jetpacks/6.2.1.conf
  2. preflight.sh runs all 12 checks
       │
       ├─ checks pass         → continue
       ├─ check fails (fatal) → print fix, exit 2
       └─ check needs sudo    → print exact command, prompt once, run via sudo
  3. cache.sh ensures ./work/cache/jp-6.2.1/ holds:
       - Jetson_Linux_R36.4.4_aarch64.tbz2          (BSP)
       - Tegra_Linux_Sample-Root-Filesystem_R36.4.4_aarch64.tbz2  (rootfs)
       - both verified by sha256 from jetpacks/6.2.1.conf
       - if missing or mismatched: download, verify, extract into ./work/Linux_for_Tegra/
  4. nfs.sh ensures ./work/Linux_for_Tegra/ is exported on 192.168.55.0/24
  5. recovery.sh waits up to 30 s for VID 0955 to appear; prints model-specific
     recovery-mode instructions if not seen
  6. flash.sh runs the container:
       podman run --rm --privileged --net host \
         -v /dev/bus/usb:/dev/bus/usb \
         -v ./work/Linux_for_Tegra:/Linux_for_Tegra \
         ghcr.io/.../jetson-restore:6.2.1 \
         /entrypoint.sh orin-nano-devkit nvme
  7. inside container, entrypoint.sh runs:
       a. apply_binaries.sh         (one-time per BSP version; gated by marker file)
       b. l4t_initrd_flash.sh with flags from jetpacks/6.2.1.conf + target conf
  8. container exits; host wrapper prints "Flash OK; reboot device to boot Ubuntu"
```

## 8. Error handling

- **Fail fast and loud, far from the device.** Preflight catches ~90% of
  failures before any USB or NFS state changes.
- **Every fatal exit prints what to do next**, not just what went wrong.
  Example: "nfs-server not running. Run `sudo systemctl start nfs-server`, or
  re-run with `--start-services` to let jetson-restore start it for you."
- **No silent retries.** A flash that retries automatically masks the
  hardware/USB issue. Print, exit, let the user re-run.
- **Container exit code propagates to the host wrapper.** The wrapper interprets
  known L4T error markers (e.g., "Failed to enter recovery mode") and adds
  context.

## 9. Testing strategy

Hardware E2E is opt-in. The first six layers below run on every PR with no
hardware.

| Layer                 | Coverage                                                                                                             | Tooling                            | Where                                               |
| --------------------- | -------------------------------------------------------------------------------------------------------------------- | ---------------------------------- | --------------------------------------------------- |
| shellcheck + shfmt    | All shell files warning-clean and formatted                                                                          | `shellcheck`, `shfmt`              | CI                                                  |
| bats-core unit tests  | Preflight checks, config parsing, target/jetpack validation, idempotency, error-message format                       | `bats-core` + `bats-assert`        | CI                                                  |
| Mock-fixture tests    | Sudo paths via PATH-injected stubs that record their args; verify exact argv and ordering, idempotency on second run | bats + shell stubs                 | CI                                                  |
| Container build test  | `Containerfile` builds clean; `apply_binaries.sh --help` runs in the resulting image                                 | `podman build`, smoke `podman run` | CI                                                  |
| Reproducibility test  | Same `--target` + `--jetpack` produces byte-identical assembled `l4t_initrd_flash.sh` argv and exports.d snippet     | bats diff                          | CI                                                  |
| Uninstall test        | `jetson-restore uninstall` removes everything preflight added; nfs-server state preserved iff the tool started it    | bats with mocked sudo              | CI                                                  |
| End-to-end (hardware) | Plug in Orin Nano dev kit and AGX Orin dev kit; flash; boot; SSH in; verify L4T release file                         | manual or self-hosted runner       | Gated by `JETSON_RESTORE_E2E=1`, run before tagging |

CI host: GitHub Actions `ubuntu-latest` for the main legs; an additional
`arch:latest` container leg catches Arch-only bash quirks.

**Not tested:** flash-time performance, content of the resulting Ubuntu rootfs
(NVIDIA's responsibility), broad podman/docker version compatibility (pin a
known-working baseline, document it).

**Release flow:**

1. Tag `v0.x.y`.
2. CI builds the container, pushes `ghcr.io/.../jetson-restore:v0.x.y` and
   `:6.2.1`.
3. GH Release auto-drafted from `CHANGELOG.md`, checksums attached.
4. Maintainer pastes E2E log, hits publish.

## 10. Prior art consulted

- NVIDIA SDK Manager Docker image — official, used by the himvis.com Yoe-AGX
  Orin walkthrough.
- SamueleFacenda NixOS gist — `ubuntu:20.04` container + host NFS +
  `l4t_initrd_flash.sh`.
- bensyz Arch Linux blog — patches needed for native L4T tools on Arch.
- Balena `jetson-flash` — Docker wrapper, but flashes balenaOS, not stock L4T.
- Anduril `jetpack-nixos`, OE4T `meta-tegra` — adjacent flash flows for
  non-Ubuntu targets.

The architecture above is most directly derived from the SamueleFacenda gist
(container + NFS export of a real host path) plus selected Arch-specific
preflight handling from the bensyz writeup, packaged as a maintained tool with
tests, pinning, and reproducibility.
