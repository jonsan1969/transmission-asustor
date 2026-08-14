# Mission Transmission Rebuild — Project State

Last updated: 2026-08-14

## Goal

Run a modern **Transmission 4.1.1** daemon on the legacy **ASUSTOR AS-608T** while preserving NAS runtime compatibility and the user's existing Transmission configuration/state.

The work remains staged and non-destructive: build and validate a standalone bundle first; only after successful NAS validation should the installed App Central package be replaced/upgraded.

## Target NAS

- Model: ASUSTOR AS-608T
- Architecture: x86-64
- Kernel: 3.12.20
- Runtime glibc: **2.22**
- Existing App Central Transmission package: Transmission 3.00, maintained by Matt
- Existing `config/` data must survive: `settings.json`, torrent/resume files, DHT state, blocklists, stats and related state.

Two independent Transmission-family services were observed on the NAS:

- Download Center: `/usr/local/AppCentral/download-center/bin/transmissiond` (root)
- App Central Transmission: `/usr/local/AppCentral/transmission/bin/transmission-daemon` (admin)

The App Central Transmission instance was observed on RPC port `9091` and peer port `53297`. Do not confuse it with Download Center during later testing.

## Build strategy

The active Build Probe uses pinned `manylinux2014_x86_64` plus **devtoolset-10 / GCC 10**. This provides a modern-enough C++17 compiler while retaining an old Linux/glibc baseline.

Selected private components:

- OpenSSL **3.5.7**
- curl **8.21.0**
- Transmission **4.1.1**
- Build dependency prefix: `/opt/transmission-deps`

Compiler flags:

```text
-O2 -march=x86-64 -mtune=generic
```

The narrow Transmission 4.1.1 GCC 10 compatibility patch remains required in `libtransmission/net.h`: remove `constexpr` only from `tr_address::is_ipv6_6to4()`. Patch commit:

`0a751f7da64ac618acfbd565eb5823e06eed8db9`

## Build Probe milestone — PASSED

GitHub Actions run **#7** proved that OpenSSL 3.5.7, curl 8.21.0 and Transmission 4.1.1 compile successfully in the selected environment and that `transmission-daemon --version` executes successfully in the builder.

The workflow was then hardened so a green run is an actual AS-608T glibc gate rather than merely a successful compilation:

- hard maximum required GLIBC: **2.22**
- audit report persisted as `transmission-abi-audit`
- GLIBCXX and CXXABI requirements recorded for private-runtime planning
- probe also runs automatically when its own workflow file changes; manual `workflow_dispatch` remains available

Relevant commits:

- `0af2fb935a5c03b04f42c7b8a51c0dd6c7898fee` — add GLIBC 2.22 gate and ABI artifact
- `d0aa327d8ce54a66d4b371f50fe22891d1593d1e` — trigger Build Probe when the probe workflow changes

GitHub Actions run **#8** (`31774327556`) completed successfully with the hard ABI gate enabled.

### Verified ABI result from run #8

All six produced Transmission executables audited at:

```text
max GLIBC:   GLIBC_2.17
max GLIBCXX: GLIBCXX_3.4.19
max CXXABI:  CXXABI_1.3.5
```

Audited programs:

- `transmission-cli`
- `transmission-daemon`
- `transmission-create`
- `transmission-edit`
- `transmission-remote`
- `transmission-show`

Private networking/crypto libraries also pass the GLIBC gate:

- `libcrypto.so.3` — GLIBC_2.17
- `libssl.so.3` — GLIBC_2.17
- `libcurl.so.4.8.0` — GLIBC_2.17

**Conclusion:** the generated Transmission/OpenSSL/curl ELF set is below the AS-608T glibc 2.22 ceiling. The basic userspace ABI strategy is therefore validated.

## Remaining runtime/bundle work

The Transmission executables currently depend on:

```text
libcurl.so.4
libssl.so.3
libcrypto.so.3
libstdc++.so.6
libgcc_s.so.1
```

plus normal system libraries (`libc`, `libm`, `libpthread`).

The current build binaries still contain this builder-only RPATH:

```text
/opt/transmission-deps/lib:/opt/transmission-deps/lib64:
```

That path is not suitable for the NAS. The standalone bundle must therefore:

1. stage Transmission executables and web assets in a self-contained test tree;
2. ship the selected private OpenSSL/curl libraries;
3. deliberately ship compatible `libstdc++.so.6` and `libgcc_s.so.1` rather than relying on ADM's old C++ runtime;
4. replace the builder RPATH with a relative private-library search path (for example `$ORIGIN/../lib`) or use a controlled wrapper/loader strategy;
5. re-audit the **staged final ELF set**, not merely the build-tree files;
6. upload the standalone bundle as a GitHub Actions artifact for NAS testing.

## NAS validation sequence after bundle creation

Before touching the installed App Central package, copy the standalone artifact to a separate NAS directory and verify at minimum:

- `file`
- program interpreter
- `ldd` / actual resolved libraries
- `transmission-daemon --version`
- daemon startup with an isolated temporary config directory and non-conflicting ports
- HTTPS/TLS certificate validation

The old local workaround `TR_CURL_SSL_NO_VERIFY=1` must **not** be carried forward.

Only after standalone NAS validation should Matt's original package layout/CONTROL scripts be adapted into an upgrade `.apk`, with explicit protection of the existing `config/` directory.

## Current next step

Build the **standalone NAS test bundle** from the now ABI-approved toolchain output, including private C++ runtime libraries and a NAS-appropriate relative library lookup, then run the ABI audit against the staged bundle itself.

## Working rule for future sessions

This file is the authoritative compact checkpoint. `docs/BUILD-NOTES.md` contains deeper technical rationale/findings; raw build logs and artifacts remain in GitHub Actions.
