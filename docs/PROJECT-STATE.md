# Mission Transmission Rebuild — Project State

Last updated: 2026-08-14

## Goal

Build and validate **Transmission 4.1.1** for legacy **ASUSTOR x86-64** NAS systems while preserving compatibility with old ADM runtimes and existing Transmission configuration/state.

The first physical validation target remains the user's **ASUSTOR AS-608T**.

## Compatibility contract

The current standalone bundle is built for:

```text
ASUSTOR x86-64 + glibc >= 2.17
```

The final staged Transmission executables audit at:

```text
GLIBC_2.17
GLIBCXX_3.4.19
CXXABI_1.3.5
```

The bundle ships its own compatible `libstdc++.so.6` and `libgcc_s.so.1`, plus private curl/OpenSSL libraries, so it does not depend on ADM providing a sufficiently new C++ runtime.

### Legacy AS-6 family

The project was created for the x64 AS-6 generation. Expected candidates include:

- AS-602T
- AS-604T
- AS-606T
- AS-608T
- AS-604RS / AS-604RD
- AS-609RS / AS-609RD

These are **expected compatible but not yet physically verified** except that the AS-608T is now partially live-validated.

Older AS-2 / AS-3 systems are 32-bit x86 and cannot use this x86-64 build.

Newer ASUSTOR x86-64 systems with glibc >= 2.17 should satisfy the binary ABI requirement, although final App Central package integration may differ by ADM generation.

## First live target: AS-608T

- Architecture: x86-64
- Kernel: 3.12.20
- Runtime glibc: **2.22**
- Existing App Central Transmission: 3.00
- Existing config/state must survive any eventual package upgrade.

Two separate Transmission-family processes exist on this NAS:

- Download Center: `/usr/local/AppCentral/download-center/bin/transmissiond` (root)
- App Central Transmission: `/usr/local/AppCentral/transmission/bin/transmission-daemon` (admin)

The App Central instance was observed on RPC port `9091` and peer port `53297`. Do not confuse it with Download Center during testing.

### Live standalone validation — in progress

The clean standalone artifact has now been unpacked on the real AS-608T under an isolated test directory.

Confirmed on physical hardware:

- `ldd` reports the NAS runtime as glibc **2.22**;
- `bin/transmission-daemon` is a 64-bit x86-64 GNU/Linux ELF using `/lib64/ld-linux-x86-64.so.2`;
- `./bin/transmission-daemon-bundled --version` executes successfully and reports **Transmission 4.1.1 (56442e2929)**;
- `ldd bin/transmission-daemon` resolves private `libcurl.so.4`, `libssl.so.3`, `libcrypto.so.3`, `libstdc++.so.6` and `libgcc_s.so.1` from the standalone bundle's own `../lib` directory;
- no staged dependency is reported as `not found`;
- certificate-verified HTTPS succeeds on the NAS using the bundled curl/OpenSSL/CA stack: `./bin/curl -I https://curl.se/` returned **HTTP/1.1 200 OK** with no `-k`, `--insecure`, or `TR_CURL_SSL_NO_VERIFY` workaround.

The daemon has not yet been started as a separate RPC/peer instance; that is the next live-validation gate.

## Current build

Versions:

- Transmission **4.1.1**
- OpenSSL **3.5.7**
- curl **8.21.0**
- GCC / G++ **10** via devtoolset-10
- pinned manylinux2014 x86-64 build environment

Compiler flags:

```text
-O2 -march=x86-64 -mtune=generic
```

Transmission 4.1.1 still receives the narrow GCC 10 source compatibility patch that removes `constexpr` only from `tr_address::is_ipv6_6to4()`.

## Standalone bundle — GREEN in CI, partial live validation GREEN

The standalone build pipeline now passes all current CI gates:

- full Transmission 4.1.1 compilation
- private OpenSSL/curl build
- private GCC runtime staging
- relocatable `$ORIGIN/../lib` runtime lookup
- no runtime dependency on `/opt/transmission-deps`
- `transmission-daemon --version` with `LD_LIBRARY_PATH` unset
- staged runtime `ldd` verification
- bundled CA trust
- real certificate-verified HTTPS request through staged curl/OpenSSL
- final staged ELF ABI audit

Latest known successful pre-cleanup standalone run:

```text
run #8 / 31779016473
commit 5473e25b86c4652903c15d3fb4484c37e0f649da
```

That run proved the corrected staged curl RPATH and completed green.

The cleaned generic ASUSTOR x86-64 workflow has also completed green under the new naming scheme.

## Clean active GitHub layout

Active build workflow:

```text
.github/workflows/build.yml
```

Workflow display name:

```text
Build Transmission 4.1.1 for ASUSTOR x86-64
```

Published bundle artifact name:

```text
transmission-4.1.1-asustor-x86_64-glibc217
```

Active build script:

```text
scripts/build-transmission-standalone.sh
```

Historical probe workflows have been removed from the active tree now that their findings are incorporated into the reproducible final build and documentation. Their history remains in Git.

## Historical ASUSTOR package findings

Archived native Transmission packages from the 2.92, 2.94 and 3.00 eras have been inspected. Durable packaging findings are recorded in:

```text
docs/PACKAGING-HISTORY.md
```

The key compatibility decision is to retain **Matt's upgrade/migration semantics** in the new package:

- preserve modern `config/` state during upgrade;
- also support migration from older layouts where state lived outside the modern `config/` tree;
- restore settings, torrent metadata, resume data, DHT state, blocklists and statistics after package replacement;
- exclude obsolete program payload (`CONTROL`, `bin`, `lib`, old web files) when migrating an older package tree.

The implementation should retain the behavior but use clean POSIX shell and explicit error handling.

Historical package inspection also showed that Matt's released ELF executables were stripped. The current standalone bundle is intentionally still unstripped during validation. Final release packaging should strip deliverable ELF files only **after** ABI/RPATH/TLS validation and then run a post-strip sanity check before creating the `.apk`.

## TLS policy

The old installed AS-608T package had a local workaround:

```sh
TR_CURL_SSL_NO_VERIFY=1; export TR_CURL_SSL_NO_VERIFY
```

It is explicitly excluded from the rebuild. The standalone bundle carries CA trust and has now passed certificate-verified HTTPS both in CI and on the physical AS-608T.

## Upgrade-data preservation

A future `.apk` must preserve existing Transmission configuration/state including:

- `settings.json`
- `.torrent` files
- resume state
- DHT state
- blocklists
- statistics

Matt's original package layout and CONTROL files remain under `package/` as the direct compatibility reference; `docs/PACKAGING-HISTORY.md` records the broader comparison against older archived packages.

## Current next step

Continue the isolated AS-608T live test by starting Transmission 4.1.1 with a fresh temporary config and non-conflicting RPC/peer ports, then verify RPC, WebUI and clean shutdown.

Do **not** touch or replace the installed App Central Transmission package until that standalone runtime test is fully successful.

## Working rule

This file is the authoritative compact project checkpoint. `docs/BUILD-NOTES.md` contains deeper technical build history, `docs/PACKAGING-HISTORY.md` contains historical App Central packaging/migration findings, and GitHub Actions holds raw build logs/artifacts.
