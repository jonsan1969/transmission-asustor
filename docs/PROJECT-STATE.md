# Mission Transmission Rebuild — Project State

Last updated: 2026-08-14 22:22 CEST

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

## First live App Central attempt — FAILED SAFELY

At 2026-08-14 21:27 local time, ADM Manual Install accepted and displayed the 4.1.1 metadata but installation returned:

```text
Install App failed. (Ref. -161)
```

After failure, App Central still showed **Transmission — Matt / 3.00**, stopped. No evidence of replacement or state loss was observed. The original run-#5 APK must not be retried.

Reinspection of Matt 3.00 exposed a concrete CONTROL compatibility gap: the old package includes `icon.png`, `icon-enable.png`, `icon-disable.png`, and `license.txt`, while the first 4.1.1 APK did not. Ref. -161 is not proven to map specifically to that omission.

## CONTROL asset correction — GREEN

Transmission 4.1.1 upstream `COPYING` was added as `package/CONTROL/license.txt`.

License commit:

```text
4d37e9025b8686d599de0e1a03fdbd3c143b6bae
```

The APK packager was hardened to restore Matt 3.00's proven 90x90 legacy ADM icons from the pinned historical APK and validate them before and after packaging. It also requires `license.txt`.

Packager commit:

```text
6a240ed444c84a353ca51f01842e958aa31a8c70
```

Pinned Matt 3.00 source APK SHA-256:

```text
f2840d2d74141233df160d3f44317d09c0bfc1f272afd8f152bd7c8d6f775cf4
```

Only the legacy presentation assets are inherited; the 4.1.1 lifecycle/start-stop implementation remains ours.

## Corrected native APK — RUN #7 GREEN

GitHub Actions:

```text
run #7
run id: 31836218637
head commit: 6a240ed444c84a353ca51f01842e958aa31a8c70
status: completed
conclusion: success
```

Artifact:

```text
name: transmission-4.1.1-asustor-x86_64-apk
artifact id: 9232775155
GitHub artifact ZIP size: 11,922,322 bytes
```

The artifact was downloaded and the finished APK was independently opened and inspected:

```text
transmission_4.1.1_x86-64.apk
size: 11,918,547 bytes
SHA-256: 06fc6ae122357d3473aaa4346a16ef02ed947a4873e452bce2341414dcdbad4e
```

`control.tar.gz` physically contains:

```text
changelog.txt
config.json
description.txt
icon.png            90x90 PNG
icon-enable.png     90x90 PNG
icon-disable.png    90x90 PNG
license.txt
post-install.sh
pre-install.sh
start-stop.sh
```

Round-trip inspection also confirmed that packaged `config/` remains empty in `data.tar.gz`.

**CORRECTED NATIVE APK / LEGACY CONTROL ASSETS: PASS.**

## First successful live App Central upgrade — INSTALLED

The corrected run-#7 APK was installed through ADM App Central Manual Install while Matt Transmission 3.00 was stopped.

App Central now reports:

```text
Transmission
maintainer: jonsan1969
version: 4.1.1
```

This confirms that ADM accepted the corrected package as the installed `transmission` application and replaced the old Matt 3.00 package registration.

The App Central detail page still displays Matt-era catalog artwork/download metadata; this is treated as stale App Central catalog presentation data, not content shipped by the new APK.

## RPC/WebUI access adjustment — APPLIED

The first WebUI access attempt returned:

```text
403: Forbidden
```

Inspection of the migrated `settings.json` showed the preserved Matt-era RPC access policy:

```text
"rpc-bind-address": "0.0.0.0",
"rpc-enabled": true,
"rpc-host-whitelist": "",
"rpc-host-whitelist-enabled": true,
"rpc-port": 9091,
"rpc-url": "/transmission/",
"rpc-whitelist": "127.0.0.1,::1",
"rpc-whitelist-enabled": true
```

This proves that the old configuration was restored rather than replaced by package defaults. For LAN WebUI access, the live configuration was adjusted while Transmission was stopped to:

```text
"rpc-whitelist": "127.0.0.1,::1,192.168.*.*",
"rpc-whitelist-enabled": true,
"rpc-host-whitelist-enabled": false
```

The original independent Matt 3.00 state backup remains untouched.

## Current next step

Start Transmission 4.1.1 from App Central and validate the live upgraded service before declaring the migration complete:

1. WebUI opens successfully on port 9091 after the RPC access adjustment;
2. daemon path/version is `/usr/local/AppCentral/transmission/bin/transmission-daemon` / Transmission 4.1.1;
3. daemon runs as `admin` and Download Center's separate root `transmissiond` remains untouched;
4. existing settings/download paths survived;
5. torrent count/state and resume data survived;
6. tracker/HTTPS operation works with verified TLS;
7. no stale isolated test daemon/tree exists.

Keep the independent Matt 3.00 state backup untouched until all live checks pass.

## Working rule — mandatory checkpoint discipline

This file is the authoritative compact checkpoint. `docs/BUILD-NOTES.md` contains deeper build rationale, `docs/PACKAGING-HISTORY.md` records historical package findings, and GitHub Actions contains raw build logs/artifacts.

Every successful code/package change and every successful build, validation or NAS test must be followed by an update to this file before the step is considered complete. Failed attempts that change diagnosis or next action must also be recorded.
