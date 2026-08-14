# Mission Transmission Rebuild — Project State

Last updated: 2026-08-14 20:45 CEST

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

**Standalone runtime on AS-608T: PASS.**

## Golden release and APKG payload — GREEN

The release finalization and minimal APKG payload phases have passed. The stripped payload remains the frozen runtime baseline for package construction.

The APKG payload contains the six Matt-compatible Transmission programs plus the required private curl/OpenSSL/C++ runtime, CA trust and WebUI. Build/test-only files were removed without changing retained runtime files.

**APKG PAYLOAD: PASS.**

The payload is approximately **29.8 MB unpacked**. Further removal is not a goal unless a file is proven unnecessary; the size is predominantly real Transmission 4.1.1 plus the modern private runtime rather than ballast.

## ASUSTOR APKG packaging phase — ACTIVE

Historical native ASUSTOR package format has been re-verified against ASUSTOR's own `apkg-tools.py` implementation:

```text
APK container: ZIP
Top-level members:
  apkg-version
  control.tar.gz
  data.tar.gz
APKG format version: 2.0
```

`control.tar.gz` contains the contents of `CONTROL/`. `data.tar.gz` contains the application payload while excluding `CONTROL/`.

### CONTROL and migration baseline

The current package keeps Matt's proven compatibility semantics while replacing his fragile implementation details:

- package ID remains `transmission`;
- daemon runs as `admin:administrators`;
- config remains `/usr/local/AppCentral/transmission/config`;
- PID file remains `/var/run/transmission-daemon.pid`;
- WebUI remains App Central port 9091;
- boot priority remains start 20 / stop 80;
- existing `config/` is backed up before upgrade;
- legacy package-root state migration is supported;
- legacy program payload is explicitly excluded from migration: `CONTROL`, `bin`, `lib`, `share`, `web`, `www`;
- post-install restore requires the explicit `.apkg-backup-complete` marker;
- package lifecycle hooks are true POSIX `/bin/sh`, not Bash `[[ ... ]]` under a sh shebang;
- binaries retain relocatable `$ORIGIN/../lib` instead of Matt's historical absolute RPATH;
- `TRANSMISSION_WEB_HOME` and TLS environment are set by service startup logic;
- historical `TR_CURL_SSL_NO_VERIFY=1` is permanently excluded.

The installed Transmission 3.00 state and roughly 600 active torrents are considered irreplaceable upgrade data. No package test may overwrite or discard them without a verified backup/restore path.

### Native APK packager added — SUCCESS

Commit:

```text
73faa41b999b336d6615977f8080fb13ac336b10
```

New script:

```text
scripts/build-asustor-apk.sh
```

The packager is designed to:

1. combine the frozen minimal payload with `package/CONTROL`;
2. force CONTROL lifecycle scripts executable in the archive;
3. ship an intentionally empty `config/` directory so no user state can be embedded in the package;
4. gate the Matt-compatible backup/restore marker and legacy exclusions before packaging;
5. reject Bash `[[ ... ]]` in CONTROL scripts;
6. re-check `$ORIGIN/../lib` on packaged Transmission executables;
7. create APKG 2.0 `apkg-version`, `control.tar.gz`, and `data.tar.gz`;
8. create `transmission_4.1.1_x86-64.apk` as a ZIP containing exactly those three members;
9. unpack both internal tarballs again and verify CONTROL/data separation, executable lifecycle hooks and empty packaged config state.

### Native APK workflow wiring — SUCCESS

Commit:

```text
bb9a07531f82c15569ba7af256595450f26428a1
```

The active workflow now:

- runs `scripts/build-asustor-apk.sh` after the existing golden-build/release/APKG-payload gates;
- uploads `transmission_4.1.1_x86-64.apk` as artifact `transmission-4.1.1-asustor-x86_64-apk`;
- uploads `asustor-apk-check.txt` even for failed APK packaging attempts;
- triggers not only on packaging-script changes but also on every `package/CONTROL/**` change, ensuring migration/service edits rebuild and revalidate the finished APK.

Result of this checkpoint: **packager and CI wiring are committed successfully; the first full native APK workflow run is now the active validation step.**

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

APKG payload finalizer:

```text
scripts/prepare-apkg-payload.sh
```

Native APK packager:

```text
scripts/build-asustor-apk.sh
```

## Current next step

1. Inspect the automatically triggered workflow for commit `bb9a07531f82c15569ba7af256595450f26428a1`.
2. If it fails, record the failure here when it changes the diagnosis and fix only the packaging layer; the frozen runtime/payload remains untouched.
3. If green, update this checkpoint with the workflow run ID, exact APK size and all packaging gates before any NAS installation work.
4. Inspect the finished APK structure and review the upgrade path against Matt 3.00 one final time.
5. Only then plan the controlled live upgrade test on the AS-608T.

Do **not** replace the installed App Central Transmission 3.00 package before the APKG migration path and the finished APK have been explicitly validated.

## Working rule — mandatory checkpoint discipline

This file is the authoritative compact project checkpoint. `docs/BUILD-NOTES.md` contains deeper technical build rationale, `docs/PACKAGING-HISTORY.md` contains historical ASUSTOR package/migration findings, and GitHub Actions holds raw build logs/artifacts.

**Every successful code/package change and every successful build, validation or NAS test must be followed by an update to `docs/PROJECT-STATE.md` before that step is considered complete.** The checkpoint must record what changed, the relevant commit/run when available, the result, and the next step.

Failed or inconclusive attempts should also be recorded when they change the diagnosis, design or next action.

Chat history is not the authoritative project record.
