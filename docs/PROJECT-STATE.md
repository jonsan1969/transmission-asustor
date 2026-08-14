# Mission Transmission Rebuild — Project State

Last updated: 2026-08-14 20:38 CEST

## Goal

Build and validate **Transmission 4.1.1** for legacy **ASUSTOR x86-64** NAS systems while preserving compatibility with old ADM runtimes and existing Transmission configuration/state.

The first physical validation target is the user's **ASUSTOR AS-608T**.

## Compatibility contract

Current bundle target:

```text
ASUSTOR x86-64 + glibc >= 2.17
```

Validated staged Transmission ABI floor:

```text
GLIBC_2.17
GLIBCXX_3.4.19
CXXABI_1.3.5
```

The bundle ships private `libstdc++.so.6`, `libgcc_s.so.1`, curl and OpenSSL libraries instead of relying on obsolete ADM C++/TLS userland.

## Current build

- Transmission **4.1.1**
- OpenSSL **3.5.7**
- curl **8.21.0**
- GCC/G++ **10** via devtoolset-10
- pinned manylinux2014 x86-64 build environment
- compiler flags: `-O2 -march=x86-64 -mtune=generic`
- narrow GCC 10 compatibility patch: remove `constexpr` only from `tr_address::is_ipv6_6to4()`
- private runtime lookup: exact relocatable `$ORIGIN/../lib`
- historical `TR_CURL_SSL_NO_VERIFY=1` workaround is permanently excluded

## AS-608T physical validation — STANDALONE GREEN

Target runtime:

- architecture: x86-64
- kernel: 3.12.20
- glibc: **2.22**
- installed App Central Transmission: 3.00

Two separate Transmission-family services exist on the NAS:

- Download Center: `/usr/local/AppCentral/download-center/bin/transmissiond` running as root
- App Central Transmission: `/usr/local/AppCentral/transmission/bin/transmission-daemon` running as admin

The existing App Central package remains untouched.

### Confirmed on the physical NAS

The standalone 4.1.1 artifact was unpacked under an isolated test directory and passed:

- x86-64 ELF execution on glibc 2.22;
- `transmission-daemon --version` -> **Transmission 4.1.1 (56442e2929)**;
- all private runtime libraries resolve from the bundle's own `../lib` directory;
- no unresolved staged dependencies;
- certificate-verified HTTPS using bundled curl/OpenSSL/CA trust with no insecure override;
- separate Transmission daemon start with fresh temporary config;
- non-conflicting RPC/WebUI instance on port **19091**;
- non-conflicting peer port **15413**;
- WebUI access through SSH port forwarding;
- successful torrent metadata/tracker/peer operation;
- successful file writes to the real download tree `/volume1/Download/Torrents`;
- WebUI Inspector/state displayed correctly with no runtime errors observed.

Windows-side SSH tunnel used during the test:

```sh
ssh -p 49522 -L 19091:127.0.0.1:19091 admin@192.168.1.160
```

WebUI during isolated test:

```text
http://127.0.0.1:19091/
```

The Ubuntu torrent used for the live torrent test announced to:

```text
http://torrent.ubuntu.com:6969
```

Therefore that torrent test itself did not exercise HTTPS tracker TLS; HTTPS was already separately validated through the bundled curl/OpenSSL/CA stack both in CI and on the NAS.

**Standalone runtime on AS-608T: PASS.**

## WebUI location

The installed Transmission 4.1.1 web assets in the standalone CMake install are under:

```text
share/transmission/public_html/
```

During the manual NAS test `TRANSMISSION_WEB_HOME` had to be exported to this directory.

For the portable standalone release wrapper it should be derived from the wrapper's bundle root. For the final ASUSTOR APKG, the equivalent environment variable belongs in the package start/stop service logic following Matt's historical package behavior.

## Release finalization phase — ACTIVE

The unstripped standalone build remains the validated baseline. Release finalization is deliberately a separate stage after the existing build/runtime/ABI/TLS gates.

New release finalizer:

```text
scripts/finalize-transmission-release.sh
```

It performs:

1. install a relocatable standalone wrapper that sets `TRANSMISSION_WEB_HOME` to `share/transmission/public_html` plus bundled CA/OpenSSL environment;
2. record pre-strip staged size;
3. strip deliverable 64-bit ELF files with `strip --strip-unneeded`;
4. record post-strip staged size and bytes saved;
5. re-run post-strip GLIBC/build-prefix audit;
6. re-check executable `$ORIGIN/../lib` RPATH;
7. re-run daemon/wrapper runtime and private-library resolution checks;
8. re-run certificate-verified HTTPS through staged curl/OpenSSL/CA;
9. rebuild the final standalone tarball and record its final archive size.

The active workflow now runs the proven standalone build/audit first and the release finalizer second.

Current workflow run triggered by this change:

```text
run #2 / 31822649054
commit b3324e7d2e20db2724c0353b268c67fb62202090
```

Status at this checkpoint: **in progress**.

Release diagnostics artifact:

```text
transmission-asustor-x86_64-release-check
```

The previous standalone archive was approximately **13 MB**; the release run will establish the actual post-strip comparison.

## Active GitHub layout

Build workflow:

```text
.github/workflows/build.yml
```

Build script:

```text
scripts/build-transmission-standalone.sh
```

Release finalizer:

```text
scripts/finalize-transmission-release.sh
```

Published bundle artifact:

```text
transmission-4.1.1-asustor-x86_64-glibc217
```

Raw validation artifacts:

```text
transmission-asustor-x86_64-runtime-check
transmission-asustor-x86_64-abi-audit
transmission-asustor-x86_64-release-check
```

## Historical ASUSTOR packaging compatibility

Archived native Transmission 2.92, 2.94 and 3.00 packages were inspected. `docs/PACKAGING-HISTORY.md` is the durable record.

Matt's 2.94/3.00 package line is the primary compatibility reference. Important behavior to carry forward:

- package tree conceptually uses `bin/`, `lib/`, `config/` and web assets;
- daemon runs as `admin:administrators`;
- config resides under `/usr/local/AppCentral/transmission/config`;
- PID file is `/var/run/transmission-daemon.pid`;
- service uses `start-stop-daemon` with start/stop/restart/reload/status, graceful wait and forced-stop fallback;
- `TRANSMISSION_WEB_HOME` is set by the start/stop service script;
- preserve existing `config/` across package upgrades;
- support migration from older layouts where state lived outside `config/`;
- preserve settings, torrent metadata, resume data, DHT state, blocklists and statistics;
- exclude obsolete package payload (`CONTROL`, `bin`, `lib`, old web assets) when migrating older package layouts;
- historical sysctl UDP-buffer tuning must not be copied blindly unless 4.1.1 proves it is still required.

The final APKG should preserve Matt's migration semantics but use clear POSIX shell and explicit error handling.

## Existing state is valuable

The installed Transmission 3.00 configuration/state and roughly 600 active torrents must not be touched until the new APKG and migration logic are ready for controlled validation.

The final package must preserve at minimum:

- `settings.json`
- `.torrent` metadata
- resume state
- DHT state
- blocklists
- statistics

## Current next step

1. Let GitHub Actions run #2 finish.
2. Inspect the release diagnostics and exact pre-/post-strip/final archive sizes.
3. If all post-strip gates are green, perform one short final runtime smoke test of that stripped artifact on the AS-608T.
4. Freeze the stripped standalone payload as the APKG payload baseline.
5. Begin the real ASUSTOR APKG around that payload using Matt-compatible start/stop and migration behavior.

Do **not** replace the installed App Central Transmission 3.00 package before the APKG migration path is explicitly validated.

## Working rule — mandatory checkpoint discipline

This file is the authoritative compact project checkpoint. `docs/BUILD-NOTES.md` contains deeper technical build rationale, `docs/PACKAGING-HISTORY.md` contains historical ASUSTOR package/migration findings, and GitHub Actions holds raw build logs/artifacts.

**Every successful code/package change and every successful build, validation or NAS test must be followed by an update to `docs/PROJECT-STATE.md` before that step is considered complete.** The checkpoint must record what changed, the relevant commit/run when available, the result, and the next step.

Failed or inconclusive attempts should also be recorded when they change the diagnosis, design or next action.

Chat history is not the authoritative project record.
