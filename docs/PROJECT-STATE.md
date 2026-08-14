# Mission Transmission Rebuild — Project State

Last updated: 2026-08-14 22:34 CEST

## Goal

Build and validate Transmission **4.1.1** for legacy ASUSTOR x86-64 / ADM while preserving the installed Matt Transmission 3.00 configuration and torrent state during a real App Central upgrade.

Primary target: **ASUSTOR AS-608T**, x86-64, glibc 2.22.

## Frozen runtime baseline — GREEN

- Transmission 4.1.1 (`56442e2929`)
- OpenSSL 3.5.7; curl 8.21.0
- manylinux2014 / glibc floor 2.17
- `GLIBCXX_3.4.19`, `CXXABI_1.3.5`
- exact relocatable `$ORIGIN/../lib`
- bundled CA trust; no `TR_CURL_SSL_NO_VERIFY=1`
- physical standalone NAS test passed daemon execution, HTTPS, WebUI/RPC, tracker/peer operation and real writes
- isolated test daemon stopped and `/volume1/home/admin/transmission-4.1.1-test` removed before live package work

## Compatibility contract with Matt 3.00

Preserve package ID `transmission`, config `/usr/local/AppCentral/transmission/config`, daemon identity `admin:administrators`, PID `/var/run/transmission-daemon.pid`, WebUI port 9091, start-order 20 / stop-order 80, `start-stop-daemon`, graceful stop with 10 second wait + SIGKILL fallback, and all user state.

Deliberate improvements remain: POSIX `/bin/sh`; no `[[ ... ]]`; relocatable RPATH; runtime-derived `TRANSMISSION_WEB_HOME`; no insecure TLS override; no unconditional old UDP sysctl tuning; explicit backup marker; `config/.` copy semantics; fail-closed lifecycle handling.

Original archived 2.92/2.94/3.00 APKs were reopened and compared directly. Matt 3.00's hooks condition state migration on `APKG_PKG_STATUS=upgrade`; old ADM Manual Install behavior still requires physical proof because the first successful 4.1.1 replacement did not restore state automatically.

## Corrected native APK — RUN #7 GREEN

GitHub Actions run #7:

```text
run id: 31836218637
head: 6a240ed444c84a353ca51f01842e958aa31a8c70
conclusion: success
```

Finished APK:

```text
transmission_4.1.1_x86-64.apk
11,918,547 bytes
SHA-256: 06fc6ae122357d3473aaa4346a16ef02ed947a4873e452bce2341414dcdbad4e
```

CONTROL physically contains `config.json`, changelog/description, upstream 4.1.1 `license.txt`, all three Matt-compatible 90x90 PNG icons, and our `pre-install.sh`, `post-install.sh`, `start-stop.sh`. Packaged `config/` is empty.

## Live App Central result

The corrected run-#7 APK installed successfully through ADM Manual Install. App Central now reports:

```text
Transmission
maintainer: jonsan1969
version: 4.1.1
```

The daemon runs from the correct path as admin and WebUI works on 9091 after adjusting the RPC policy to allow the local LAN.

However direct filesystem inspection after the automatic package replacement showed:

```text
/usr/local/AppCentral/transmission/config/torrents -> 0 files
/usr/local/AppCentral/transmission/config/resume   -> 0 files
```

WebUI therefore showed **0 Transfers**.

**LIVE PACKAGE INSTALL: PASS.**
**AUTOMATIC 3.00 STATE MIGRATION: FAIL.**

The package/runtime is functional, but the lifecycle backup/restore path did not preserve the existing Matt 3.00 state during this Manual Install. Do not infer the reason until ADM/package-manager evidence proves it.

## Independent Matt 3.00 backups — VERIFIED

The exact independent backups are:

```text
/volume1/Download/transmission-3.00-full-backup.tar.gz
/volume1/Download/transmission-3.00-config-backup.tar.gz
```

Do not substitute similarly named archives elsewhere on the NAS.

The config backup was inspected read-only with `tar -tzf`; archive root:

```text
usr/local/AppCentral/transmission/config/
```

Verified contents include:

```text
settings.json
stats.json
dht.dat
blocklists/blocklist.bin
blocklists/newid.bin
torrents/*.torrent
resume/*.resume
```

Exact extension-only counts in the restored tree are:

```text
533 *.torrent
533 *.resume
```

**INDEPENDENT CONFIG BACKUP CONTENTS: PASS.**

## Manual Matt 3.00 state restore — PASS

With Transmission 4.1.1 stopped, the empty/new 4.1.1 config tree was preserved as:

```text
/usr/local/AppCentral/transmission/config.empty-4.1.1
```

The verified config backup was restored to `/` using its observed archive structure, recreating:

```text
/usr/local/AppCentral/transmission/config
```

Ownership was corrected recursively to `admin:administrators`.

Post-restore exact counts:

```text
/usr/local/AppCentral/transmission/config/torrents -> 533 *.torrent
/usr/local/AppCentral/transmission/config/resume   -> 533 *.resume
```

**MANUAL STATE RESTORE: PASS.**

Both independent backup archives remain untouched and must stay that way until the restored 4.1.1 installation is fully validated.

## Immediate next step

1. Keep Transmission 4.1.1 stopped while editing the restored old `settings.json`.
2. Reapply only the required LAN RPC access adjustment to the restored settings:
   - `rpc-whitelist`: `127.0.0.1,::1,192.168.*.*`
   - `rpc-whitelist-enabled`: `true`
   - `rpc-host-whitelist-enabled`: `false`
3. Start 4.1.1 from App Central.
4. Verify WebUI shows the restored 533 transfers/state rather than 0.
5. Verify daemon version/path/user, download paths, resume state, tracker/HTTPS operation and Download Center isolation.
6. Separately determine why old ADM Manual Install skipped automatic migration, then fix/rebuild the package hooks before release.

## Working rule — mandatory checkpoint discipline

This file is the authoritative compact checkpoint. `docs/BUILD-NOTES.md` contains deeper build rationale, `docs/PACKAGING-HISTORY.md` records historical package findings, and GitHub Actions contains raw build logs/artifacts.

Every successful code/package change and every successful build, validation or NAS test must be followed by an update to this file before the step is considered complete. Failed attempts that change diagnosis or next action must also be recorded.

Chat history is not the authoritative project record.
