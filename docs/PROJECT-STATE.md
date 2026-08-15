# Mission Transmission Rebuild — Project State

Last updated: 2026-08-15 08:50 CEST

## Goal

Build and validate Transmission **4.1.1** for legacy ASUSTOR x86-64 / ADM while preserving the installed Matt Transmission 3.00 configuration and torrent state during a real App Central replacement/upgrade.

Primary physical target: **ASUSTOR AS-608T**, x86-64, glibc 2.22.

## Frozen runtime baseline — GREEN

- Transmission 4.1.1 (`56442e2929`)
- OpenSSL 3.5.7 / curl 8.21.0
- manylinux2014 / max audited `GLIBC_2.17`
- `GLIBCXX_3.4.19`, `CXXABI_1.3.5`
- exact relocatable `$ORIGIN/../lib`
- bundled CA trust; no `TR_CURL_SSL_NO_VERIFY=1`
- standalone NAS test passed daemon, RPC/WebUI, HTTPS, tracker/peer operation and real writes

## Matt 3.00 compatibility contract

Preserve package ID `transmission`, config path `/usr/local/AppCentral/transmission/config`, daemon identity `admin:administrators`, PID `/var/run/transmission-daemon.pid`, port 9091, start-order 20 / stop-order 80, `start-stop-daemon`, graceful stop + SIGKILL fallback and all user state.

Deliberate improvements remain: true POSIX `/bin/sh`; no `[[ ... ]]`; relocatable RPATH; runtime-derived `TRANSMISSION_WEB_HOME`; verified TLS; no unconditional legacy UDP sysctl tuning; explicit migration marker; `config/.` copy semantics.

## Native APK / live runtime — PASS

Run #7 produced the corrected native APKG 2.0 with legacy ADM icons and upstream Transmission license notice. The package installed successfully through ADM Manual Install.

Live NAS validation after manual state recovery:

- App Central reports `jonsan1969 / 4.1.1`
- daemon: `/usr/local/AppCentral/transmission/bin/transmission-daemon`
- version: `transmission-daemon 4.1.1 (56442e2929)`
- daemon user: `admin`
- WebUI/Remote GUI works on 9091
- initial recovery had **533 `.torrent` + 533 `.resume`**; later live baseline reached **534/534** through legitimate torrent activity
- HTTPS tracker communication works
- real peer upload/seeding observed from restored state
- external tracker profile identifies `Transmission/4.1.1`

Exact untouched independent backups:

```text
/volume1/Download/transmission-3.00-full-backup.tar.gz
/volume1/Download/transmission-3.00-config-backup.tar.gz
```

## Automatic migration bug — ROOT CAUSE CLASS IDENTIFIED

The first successful old-ADM Manual Install replaced Matt 3.00 with 4.1.1 but produced empty `torrents/` and `resume/` directories. Our lifecycle scripts treated `APKG_PKG_STATUS=install` as an unconditional clean install and only protected state for `upgrade`.

Observed Manual Install behavior proves that assumption is unsafe on this ADM generation. The package replacement can occur through the `install` lifecycle path.

Do not claim the exact ADM environment value is independently logged yet; the fix is intentionally status-robust instead of depending on that unproven detail.

## Migration hardening — CI GREEN

Migration hardening commit:

```text
ffd4b5c3cf1508404968cc2d05405518c9c0d225
```

CI test-harness fix:

```text
b2ce9394f2fade97cbdbaeab9485c3875592a252
```

GitHub Actions **run #9 / run ID 31865580032** completed successfully.

Native APK:

```text
Artifact ID: 9241979173
APK filename: transmission_4.1.1_x86-64.apk
APK size: 11918683 bytes
APK SHA-256: dfa339d4eb2f7e9509a6d776b58fbfb8bf82f6424a841efa188e86d176702f6c
```

Physical APK inspection passed: correct APKG 2.0 members, executable lifecycle hooks, empty packaged `config/`, migration markers present, and NAS ownership logic retained.

## Physical validation campaign — IN PROGRESS

### Same-version reinstall

ADM Manual Install refuses `4.1.1 -> 4.1.1` before lifecycle execution with:

```text
The same version of this App has already been installed. (Ref. 6001)
```

Therefore same-version reinstall is **N/A on this ADM generation** and is not a valid migration test.

### Pre-wipe 4.1.1 baseline

Before cleanup the active 4.1.1 instance was healthy with **534 torrents + 534 resume files**. A second Transmission-family process was identified as Download Center's independent root-owned `transmissiond`, using `/usr/local/AppCentral/download-center/etc` rather than the App Central Transmission config.

### Uninstall / zero-state result

Transmission 4.1.1 was stopped and removed through App Central. ADM removed `/usr/local/AppCentral/transmission` completely and left no Transmission init/script residue.

Download Center was unused and was also removed through App Central. The resulting zero-state was verified:

- no Transmission daemon process
- no `transmission` or `download-center` directory under `/usr/local/AppCentral`
- no related startup entries under `/usr/local/etc`
- no Transmission PID residue
- both independent Matt 3.00 backups remained untouched

Download Center does not need to be reinstalled after testing.

### Matt 3.00 clean-install baseline — PASS

Matt Transmission 3.00 was installed fresh from App Central on the verified zero-state NAS.

Observed at 2026-08-15 08:47 CEST:

- daemon: `/usr/local/AppCentral/transmission/bin/transmission-daemon`
- daemon user: `admin`
- version: `transmission-daemon 3.00 (bb6b5a062e)`
- clean WebUI loads successfully with **0 Transfers**
- clean `config/` contains `blocklists/`, `resume/`, `torrents/`, and newly generated `settings.json`
- torrent count = 0
- resume count = 0
- package root and payload are owned `admin:administrators` on this clean Matt install

The original Matt lifecycle scripts were captured before restoring user state. They use Bash-style `[[ ... ]]` despite `#!/bin/sh`, upgrade-only config copying through `APKG_TEMP_DIR`, unconditional `chown -R admin:administrators`, legacy UDP sysctl tuning, fixed WebUI path, and the same daemon identity/PID/start-stop behavior already used as our compatibility baseline.

### Install prerequisite dialog finding

A clean **App Central catalog install** of Matt 3.00 displays the legacy prerequisite dialog showing:

- required shared folder: `Download`
- default Transmission port: `9091`
- optional `Enable port forwarding for Transmission` checkbox

Matt's original `CONTROL/config.json` was captured and its relevant `register` metadata is structurally the same as our 4.1.1 `config.json`: `Download` share-folder, port `[9091]`, boot priority 20/80, and empty enable/restart-service prerequisite arrays.

Therefore do **not** attribute this dialog to Matt's `pre-install.sh`. It may depend on ADM's catalog-install path versus Manual Install. This remains to be tested during the final clean 4.1.1 Manual Install; do not claim the dialog is missing from our package unless that clean test proves it.

## Mandatory next steps

1. Stop the clean Matt 3.00 daemon.
2. Inspect the two existing Matt 3.00 backup archive layouts before extracting anything.
3. Restore the known-good Matt 3.00 user state and verify 3.00 operation fully.
4. Install the run #9 4.1.1 APK through ADM Manual Install with **no manual migration repair**.
5. Verify automatic state preservation, daemon identity, WebUI/Remote GUI, paths, tracker communication and real transfer activity.
6. Take a new 4.1.1 backup.
7. Wipe Transmission again, install 4.1.1 clean via Manual Install, verify genuine blank-install behavior (including whether ADM shows the prerequisite dialog), then restore the 4.1.1 backup and revalidate.

Do not delete the two independent Matt 3.00 backups until the full campaign is complete.

## Working rule — mandatory checkpoint discipline

This file is the authoritative compact checkpoint. Update it after every successful code/package change and every successful build, validation or NAS test before that step is considered closed.
