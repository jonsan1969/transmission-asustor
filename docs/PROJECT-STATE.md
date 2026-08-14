# Mission Transmission Rebuild — Project State

Last updated: 2026-08-14 21:20 CEST

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

### Standalone test environment cleanup — PASS

Before the live package upgrade, the isolated 4.1.1 test daemon was confirmed stopped. Process inspection showed only ASUSTOR Download Center's separate Transmission-family daemon:

```text
/usr/local/AppCentral/download-center/bin/transmissiond
```

No process from `/volume1/home/admin/transmission-4.1.1-test` remained, and the isolated test tree was then removed successfully.

**ISOLATED TEST BUILD CLEANUP: PASS.**

## Golden release and APKG payload — GREEN

The release finalization and minimal APKG payload phases have passed. The stripped payload remains the frozen runtime baseline for package construction.

The APKG payload contains the six Matt-compatible Transmission programs plus the required private curl/OpenSSL/C++ runtime, CA trust and WebUI. Build/test-only files were removed without changing retained runtime files.

**APKG PAYLOAD: PASS.**

The payload is approximately **29.8 MB unpacked**. Further removal is not a goal unless a file is proven unnecessary; the size is predominantly real Transmission 4.1.1 plus the modern private runtime rather than ballast.

## ASUSTOR APKG packaging phase — NATIVE APK GREEN

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

The packager:

1. combines the frozen minimal payload with `package/CONTROL`;
2. forces CONTROL lifecycle scripts executable in the archive;
3. ships an intentionally empty `config/` directory so no user state can be embedded in the package;
4. gates the Matt-compatible backup/restore marker and legacy exclusions before packaging;
5. rejects Bash `[[ ... ]]` in CONTROL scripts;
6. re-checks `$ORIGIN/../lib` on packaged Transmission executables;
7. creates APKG 2.0 `apkg-version`, `control.tar.gz`, and `data.tar.gz`;
8. creates `transmission_4.1.1_x86-64.apk` as a ZIP containing exactly those three members;
9. unpacks both internal tarballs again and verifies CONTROL/data separation, executable lifecycle hooks and empty packaged config state.

### Native APK workflow wiring — SUCCESS

Commit:

```text
bb9a07531f82c15569ba7af256595450f26428a1
```

The active workflow:

- runs `scripts/build-asustor-apk.sh` after the existing golden-build/release/APKG-payload gates;
- uploads `transmission_4.1.1_x86-64.apk` as artifact `transmission-4.1.1-asustor-x86_64-apk`;
- uploads `asustor-apk-check.txt` even for failed APK packaging attempts;
- triggers not only on packaging-script changes but also on every `package/CONTROL/**` change, ensuring migration/service edits rebuild and revalidate the finished APK.

### First complete native APK build — PASS

GitHub Actions:

```text
run #5
run id: 31829954975
head commit: bb9a07531f82c15569ba7af256595450f26428a1
conclusion: success
```

Finished package:

```text
transmission_4.1.1_x86-64.apk
11,893,267 bytes
```

The downloaded finished artifact was independently opened after the successful workflow run and confirmed to be a ZIP-format ASUSTOR APKG with exactly:

```text
apkg-version     4 bytes, content: 2.0
control.tar.gz   2,236 bytes
data.tar.gz      11,927,351 bytes
```

Round-trip inspection confirmed:

- top-level APK structure is exactly the required three members;
- `control.tar.gz` contains the expected package metadata and lifecycle scripts;
- `data.tar.gz` contains the six Transmission binaries and the frozen private runtime/WebUI payload;
- `CONTROL/` is not present in `data.tar.gz`;
- packaged `config/` exists only as an empty directory;
- no `settings.json`, torrent metadata, resume state, DHT state, blocklists or other user state is embedded in the APK;
- the workflow's APK packaging/validation gate completed successfully.

Artifact:

```text
transmission-4.1.1-asustor-x86_64-apk
GitHub artifact id: 9230465775
```

**NATIVE ASUSTOR APK BUILD: PASS.**

## Original package re-review — UPGRADE PATH GREEN

Before any live upgrade, the original archived APKs were opened again directly:

```text
Matt Transmission 3.00 x86-64
Matt Transmission 2.94 x86-64
Transmission 2.92 x86-64
Transmission Dansk 2.92 x86-64
Fathi Boudra Transmission 2.92-1 x86-64
```

The actual CONTROL archives confirm that Matt 3.00 and 2.94 preserve `${PKG_DIR}/config` through `${APKG_TEMP_DIR}` during upgrade and restore it into the new package. The 4.1.1 scripts preserve the same semantics but harden them:

- copy `config/.` rather than `config/*`, preserving hidden state;
- isolate backup under `${APKG_TEMP_DIR}/transmission-config-backup`;
- require `.apkg-backup-complete` before restore;
- reject unsupported package status instead of silently continuing;
- retain legacy package-root migration while excluding `CONTROL`, `bin`, `lib`, `share`, `web`, `www` program payload;
- use strict POSIX `/bin/sh` rather than Matt's `[[ ... ]]` Bash-isms.

The start/stop comparison also confirms that the 4.1.1 package intentionally retains Matt-compatible service semantics:

```text
user/group: admin:administrators
PID file:   /var/run/transmission-daemon.pid
config:     /usr/local/AppCentral/transmission/config
service:    start-stop-daemon
commands:   start/stop/restart/reload/status
graceful stop timeout: 10 seconds, then SIGKILL fallback
```

Implementation details deliberately not copied from Matt include hard-coded WebUI/package paths, unconditional UDP-buffer sysctl tuning, `/lib/lsb/init-functions` dependency, and Bash-style conditionals under `#!/bin/sh`. The new package derives paths from `APKG_PKG_DIR`, sets `TRANSMISSION_WEB_HOME` at runtime and keeps the verified `$ORIGIN/../lib` private-library lookup.

For the actual installed **Matt 3.00 -> Transmission 4.1.1** path on the AS-608T, no state-loss mismatch was found in pre-install backup, package replacement assumptions, post-install restore or service identity.

**LEGACY APK / 3.00 UPGRADE-PATH REVIEW: PASS.**

Historical details are recorded in `docs/PACKAGING-HISTORY.md`; review update commit: `cb8c1c757ad688cf143912e88a82fe2a0ffa7de4`.

## Independent live-state backup

An independent out-of-band backup of the existing Matt 3.00 Transmission configuration/state had already been created before this stage of the project. It remains the safety copy for the first live package upgrade and must not be removed until 4.1.1 has been fully validated with the real state.

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

The build, finished APK, original-package upgrade review, independent state backup and isolated test cleanup are complete.

Next: perform the first controlled live App Central upgrade from Matt Transmission 3.00 to Transmission 4.1.1.

Immediately after installation, verify before declaring success:

1. daemon version is Transmission 4.1.1;
2. process identity/path is the App Central Transmission daemon, not Download Center;
3. RPC/WebUI responds on port 9091;
4. existing settings and download paths survived;
5. torrent count/state and resume data survived;
6. trackers/HTTPS operate correctly with proper certificate verification;
7. no duplicate test daemon or stale isolated test tree exists.

Keep the independent Matt 3.00 state backup untouched until the live upgrade is fully validated.

## Working rule — mandatory checkpoint discipline

This file is the authoritative compact project checkpoint. `docs/BUILD-NOTES.md` contains deeper technical build rationale, `docs/PACKAGING-HISTORY.md` contains historical ASUSTOR package/migration findings, and GitHub Actions holds raw build logs/artifacts.

**Every successful code/package change and every successful build, validation or NAS test must be followed by an update to `docs/PROJECT-STATE.md` before that step is considered complete.** The checkpoint must record what changed, the relevant commit/run when available, the result, and the next step.

Failed or inconclusive attempts should also be recorded when they change the diagnosis, design or next action.

Chat history is not the authoritative project record.
