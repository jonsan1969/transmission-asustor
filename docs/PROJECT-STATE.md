# Mission Transmission Rebuild — Project State

Last updated: 2026-08-14 22:06 CEST

## Goal

Build and validate Transmission **4.1.1** for legacy ASUSTOR x86-64 / ADM while preserving the installed Matt Transmission 3.00 configuration and torrent state during a real App Central upgrade.

Primary target: **ASUSTOR AS-608T**, x86-64, glibc 2.22.

## Frozen runtime baseline — GREEN

- Transmission 4.1.1 (`56442e2929`)
- OpenSSL 3.5.7
- curl 8.21.0
- manylinux2014 / glibc floor 2.17
- `GLIBCXX_3.4.19`, `CXXABI_1.3.5`
- private runtime via exact relocatable `$ORIGIN/../lib`
- bundled CA trust; no `TR_CURL_SSL_NO_VERIFY=1`
- isolated physical NAS test passed daemon execution, HTTPS, WebUI/RPC, tracker/peer operation and real writes
- isolated test daemon stopped and `/volume1/home/admin/transmission-4.1.1-test` removed before live package work

## Compatibility contract with Matt 3.00

Preserve:

- package ID `transmission`
- config `/usr/local/AppCentral/transmission/config`
- daemon identity `admin:administrators`
- PID `/var/run/transmission-daemon.pid`
- App Central/WebUI port 9091
- start-order 20 / stop-order 80
- `start-stop-daemon`
- graceful stop with 10 second wait and SIGKILL fallback
- upgrade backup/restore of settings, torrents, resume data, DHT, stats and blocklists
- legacy package-root migration while excluding program payload (`CONTROL`, `bin`, `lib`, `share`, `web`, `www`)

Deliberate improvements over Matt:

- POSIX `/bin/sh`; no Bash `[[ ... ]]`
- relocatable `$ORIGIN/../lib`, not absolute RPATH
- runtime-derived `TRANSMISSION_WEB_HOME`
- no insecure TLS override
- no unconditional historical UDP sysctl tuning
- explicit backup-complete marker before restore
- copy `config/.` so hidden files are preserved
- fail closed on unsupported/incomplete upgrade environment

Original archived 2.92/2.94/3.00 APKs were re-opened and compared directly. The **3.00 -> 4.1.1 state migration path remains approved**.

## Independent live-state backup

An out-of-band backup of the installed Matt 3.00 state was already created before the first live package attempt. Keep it untouched until the live 4.1.1 upgrade is fully validated.

## Native APK build before first live attempt

GitHub Actions run #5 / run id `31829954975` produced a structurally valid APKG 2.0:

```text
transmission_4.1.1_x86-64.apk
11,893,267 bytes
```

The package contained exactly `apkg-version`, `control.tar.gz`, `data.tar.gz`; user `config/` was empty in the payload; migration/service gates passed.

## First live App Central attempt — FAILED SAFELY

At 2026-08-14 21:27 local time, ADM Manual Install accepted and displayed the 4.1.1 metadata but installation returned:

```text
Install App failed. (Ref. -161)
```

After failure, App Central still showed **Transmission — Matt / 3.00**, stopped. No evidence of replacement or state loss was observed. Do not retry the same APK.

Reinspection of the original Matt 3.00 CONTROL archive exposed a presentation/legacy-ADM compatibility gap in our first APK: Matt ships:

```text
icon.png
icon-enable.png
icon-disable.png
license.txt
```

Our first APK omitted those files. The exact meaning of ADM Ref. -161 is not proven, so the omission is treated as a concrete package defect/candidate cause rather than a proven error-code mapping.

## CONTROL asset correction — CODE CHANGED, REBUILD REQUIRED

Transmission 4.1.1's current `COPYING` text was taken from the upstream `4.1.1` tag and added as:

```text
package/CONTROL/license.txt
```

Commit:

```text
4d37e9025b8686d599de0e1a03fdbd3c143b6bae
```

The APK packager was then hardened to restore Matt 3.00's proven 90x90 legacy ADM icons from the pinned historical ASUSTOR APK, with SHA-256 verification before extraction:

```text
source: https://appdownload.asustor.com/0010_54837_1590279933_transmission_3.00_x86-64.apk
SHA-256: f2840d2d74141233df160d3f44317d09c0bfc1f272afd8f152bd7c8d6f775cf4
```

Only `icon.png`, `icon-enable.png`, and `icon-disable.png` are extracted into the new CONTROL tree. The packager validates PNG signature, IHDR and exact 90x90 dimensions, requires the three icons plus `license.txt`, and verifies them again after `control.tar.gz` round-trip.

Packager commit:

```text
6a240ed444c84a353ca51f01842e958aa31a8c70
```

This preserves our own 4.1.1 lifecycle/start-stop implementation; only the proven legacy ADM presentation assets are inherited from Matt.

## Mandatory next step

1. Wait for the GitHub Actions build triggered by the CONTROL/packager changes.
2. Require the complete workflow and native APK gate to pass.
3. Download and inspect the newly built APK, confirming `license.txt` and all three 90x90 PNG icons are physically present in `control.tar.gz` alongside the existing lifecycle scripts.
4. Update this checkpoint with the green run ID/artifact/hash/size.
5. Only then retry Manual Install on the AS-608T while Matt 3.00 remains stopped.

Do **not** install the old run-#5 APK again.

## Working rule — mandatory checkpoint discipline

This file is the authoritative compact checkpoint. `docs/BUILD-NOTES.md` contains deeper build rationale, `docs/PACKAGING-HISTORY.md` records historical package findings, and GitHub Actions contains raw build logs/artifacts.

Every successful code/package change and every successful build, validation or NAS test must be followed by an update to this file before the step is considered complete. Failed attempts that change diagnosis or next action must also be recorded.
