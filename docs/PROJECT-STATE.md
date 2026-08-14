# Mission Transmission Rebuild — Project State

Last updated: 2026-08-14

## Goal

Run a modern **Transmission 4.1.1** daemon on a legacy **ASUSTOR AS-608T** while preserving compatibility with the NAS runtime and preserving the user's existing Transmission data/configuration.

The work is intentionally staged and non-destructive. We build and validate outside the installed App Central package first; only after successful NAS validation do we build/install an upgrade package.

## Target NAS

- Model: ASUSTOR AS-608T
- Architecture: x86-64
- Kernel: 3.12.20
- Runtime glibc: 2.22
- Existing App Central Transmission package: Transmission 3.00, maintained by Matt
- Existing package config/data must survive an upgrade: `settings.json`, `.torrent` files, resume state, DHT state, blocklists, stats and related config data.

### Current installed-process observation

During live inspection the NAS was running two Transmission-family daemons at once:

- Download Center-owned `transmissiond`, running as root from `/usr/local/AppCentral/download-center/`
- App Central Transmission `transmission-daemon`, running as admin from `/usr/local/AppCentral/transmission/`

The standalone Transmission instance was observed listening on RPC port `9091` and peer port `53297`. This distinction matters when later testing/replacing the App Central Transmission package: do not confuse it with Download Center's separate daemon.

## Packaging/upgrade constraints

- Retain Matt's original package layout and CONTROL scripts as compatibility reference.
- The new package must not destroy or reset the existing `config/` directory.
- Build a standalone test bundle first and copy it to a separate NAS directory.
- Validate the standalone binary with at least `--version`, `file`, `ldd`, loader/library checks and actual daemon startup before touching the installed package.
- Only after successful standalone validation should an ASUSTOR `.apk` upgrade package be produced and tested.

### TLS / certificate policy

The installed package was locally modified in 2022 with:

```sh
TR_CURL_SSL_NO_VERIFY=1; export TR_CURL_SSL_NO_VERIFY
```

This was a local HTTPS workaround, not part of Matt's original package. It must **not** be carried forward. The rebuilt package should use proper CA certificate verification.

## Build strategy

The legacy ASUSTOR package already follows a private-library model, shipping its own libraries under the application directory rather than depending entirely on ADM's old system stack. The rebuild follows the same principle.

Current direction:

1. Establish the NAS/toolchain ABI target.
2. Use a modern compiler that can build Transmission 4.1.1 while keeping the generated runtime requirements old enough for the AS-608T.
3. Build modern private dependencies rather than using the NAS SSL/curl stack.
4. Audit every produced ELF for runtime requirements before NAS deployment.
5. Produce a standalone bundle before packaging.

## Current build environment

The active Build Probe uses a pinned `manylinux2014_x86_64` container and enables **devtoolset-10 / GCC 10**.

Compiler flags:

```text
-O2 -march=x86-64 -mtune=generic
```

Transmission language targets:

- C11
- C++17

This environment is being used because the original ASUSTOR cross-toolchain is too old for modern Transmission C++ code, while manylinux2014 provides an old-enough glibc baseline combined with a newer compiler.

## Private dependency versions currently selected

- OpenSSL: **3.5.7**
- curl: **8.21.0**
- Transmission: **4.1.1**
- Private dependency prefix in Build Probe: `/opt/transmission-deps`

The Build Probe currently builds OpenSSL shared libraries, then curl against that OpenSSL, then configures/builds Transmission against the private prefix.

## GitHub Actions workflows

- `.github/workflows/toolchain-probe.yml` — probes ASUSTOR's official legacy x86-64 toolchain and target ABI.
- `.github/workflows/modern-abi-probe.yml` — checks whether a modern C++17 compiler environment can still produce an appropriately old ABI/runtime baseline.
- `.github/workflows/transmission-build-probe.yml` — builds OpenSSL, curl and Transmission 4.1.1 and audits the resulting ELF binaries.

All current probe workflows are manually triggered with `workflow_dispatch`.

## Build Probe progress

### Proven working so far

- Pinned manylinux2014 build environment starts successfully.
- GCC/G++ 10 build environment is active.
- Required OpenSSL Perl prerequisites are installed in the probe.
- OpenSSL 3.5.7 builds and installs into the private prefix.
- Private OpenSSL runtime lookup was fixed so the freshly built tools can execute inside the probe.
- curl 8.21.0 builds against the private OpenSSL.
- Transmission 4.1.1 source checkout succeeds.
- CMake configuration of Transmission against the private dependency prefix succeeds.
- The build reaches actual `libtransmission` C++ compilation.

### Current compiler compatibility fix

Build Probe run based on commit `016c3df27df5732ce2ea67d19eecf2ae5ed5d1f5` failed in `libtransmission/net.h` at `tr_address::is_ipv6_6to4()`.

GCC 10 rejected the `constexpr` function because glibc's `htons()` implementation introduces a temporary that GCC 10 regards as uninitialized inside a constexpr function:

```text
error: uninitialized variable '__v' in 'constexpr' function
```

Transmission 4.1.1 upstream contains:

```cpp
[[nodiscard]] constexpr bool is_ipv6_6to4() const noexcept
{
    return is_ipv6() && reinterpret_cast<uint16_t const*>(&addr.addr6)[0] == htons(0x2002U);
}
```

The Build Probe now applies a narrow fail-loud compatibility patch after cloning Transmission and before CMake configuration:

```sh
grep -q "constexpr bool is_ipv6_6to4() const noexcept" /tmp/transmission-src/libtransmission/net.h
sed -i "/is_ipv6_6to4() const noexcept/s/constexpr //" /tmp/transmission-src/libtransmission/net.h
grep -n -B2 -A3 "is_ipv6_6to4" /tmp/transmission-src/libtransmission/net.h
```

The patch removes `constexpr` only from `is_ipv6_6to4()`; runtime semantics are unchanged.

Patch commit:

`0a751f7da64ac618acfbd565eb5823e06eed8db9` — **Fix Transmission 4.1.1 GCC 10 constexpr build failure**

## ABI audit requirements

After a successful Transmission build, the probe must inspect the generated executables and private shared libraries for:

- ELF architecture/type
- program interpreter
- `NEEDED` libraries
- `RPATH` / `RUNPATH`
- maximum referenced `GLIBC_*`
- maximum referenced `GLIBCXX_*`
- maximum referenced `CXXABI_*`

The Build Probe already contains these checks. A successful compilation is **not** enough; the ABI audit is a release gate before the NAS test bundle is created.

## Current next step

Run **Transmission 4.1.1 Build Probe** at commit `0a751f7da64ac618acfbd565eb5823e06eed8db9` and inspect whether compilation advances past the GCC 10 `is_ipv6_6to4()` failure.

If the build succeeds, review the complete ELF/ABI audit before moving to standalone-bundle construction.

If it fails, preserve the first real compiler/linker error (not merely the final `gmake` exit code) and update this file with the new blocker and decision.

## Working rule for future sessions

This file is the authoritative compact checkpoint for the project. After meaningful decisions or successful/failed milestones, update `docs/PROJECT-STATE.md` before considering that milestone complete.

Raw logs remain in GitHub Actions. Detailed technical reasoning and historical findings belong in `docs/BUILD-NOTES.md`. The chat is the working discussion layer, not the sole project memory.
