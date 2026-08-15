# Mission Transmission Rebuild — Project State

Last updated: 2026-08-15 09:06 CEST

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

- App Central reports 4.1.1
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

## Automatic migration bug — FIX PHYSICALLY VALIDATED

The first successful old-ADM Manual Install replaced Matt 3.00 with 4.1.1 but produced empty `torrents/` and `resume/` directories. Our lifecycle scripts treated `APKG_PKG_STATUS=install` as an unconditional clean install and only protected state for `upgrade`.

Migration hardening made lifecycle handling status-robust: existing real state is backed up for install-labelled replacement as well as upgrade, and restored only with a completed backup marker.

Do not claim the exact ADM environment value is independently logged; the fix deliberately does not depend on it.

### CI evidence

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

### Physical Matt 3.00 -> 4.1.1 migration — PASS

On 2026-08-15 the NAS was first returned to a verified zero-state: Transmission 4.1.1 and unused Download Center were removed through App Central, leaving no Transmission daemon, package directory, startup residue or PID residue.

Matt Transmission 3.00 was then installed clean from App Central. The clean baseline was `transmission-daemon 3.00 (bb6b5a062e)`, 0 transfers, and a newly generated empty config.

The independent 3.00 config backup was restored while stopped. It contained exactly **533 `.torrent` + 533 `.resume`** files. The old working `CONTROL/start-stop.sh` from the full backup was also restored because that historical 3.00 installation required `TR_CURL_SSL_NO_VERIFY=1` for HTTPS trackers. Matt 3.00 was started and Remote GUI showed all **533 transfers** correctly.

The exact run #9 `transmission_4.1.1_x86-64.apk` was then installed through **ADM Manual Install directly over the working Matt 3.00 installation**, with **no SSH/manual state repair after installation**.

Observed at 2026-08-15 09:05 CEST:

- daemon started automatically as `admin`
- daemon path remained `/usr/local/AppCentral/transmission/bin/transmission-daemon`
- version became `transmission-daemon 4.1.1 (56442e2929)`
- torrent count remained **533**
- resume count remained **533**
- Remote GUI immediately showed **533 transfers** with labels/state intact
- restored config contains historical `dht.dat`, `stats.json`, torrents and resume state; 4.1.1 generated/updated its expected settings files
- package payload is the new root-owned 4.1.1 tree while config remains `admin:administrators`
- no manual migration repair was required

**The automatic Matt 3.00 -> 4.1.1 state-preservation bug is therefore physically fixed on the target AS-608T.**

One cosmetic/ADM registry observation remains: after replacement App Central's Installed view displays `Matt / 4.1.1`, even though the Manual Install review dialog correctly showed maintainer `jonsan1969`. Investigate separately; it did not affect runtime migration.

## Physical validation campaign — remaining work

### Same-version reinstall

ADM Manual Install refuses `4.1.1 -> 4.1.1` before lifecycle execution with:

```text
The same version of this App has already been installed. (Ref. 6001)
```

Therefore same-version reinstall is **N/A on this ADM generation**.

### Install prerequisite dialog finding

A clean **App Central catalog install** of Matt 3.00 displays the legacy prerequisite dialog showing required `Download` share, port 9091 and optional port-forwarding checkbox.

Matt's original `CONTROL/config.json` and our 4.1.1 package have structurally equivalent relevant register metadata. The 3.00 -> 4.1.1 Manual Install replacement showed the unverified-App review dialog rather than the prerequisite dialog. Do not conclude anything is missing until a final **clean 4.1.1 Manual Install** is tested from zero-state.

## Mandatory next steps

1. Perform a little runtime sanity checking on the successfully migrated 4.1.1 (WebUI/Remote GUI already passed; tracker/peer activity can be observed if available).
2. Take a new independent **4.1.1 backup** while stopped, preserving the current known-good migrated state.
3. Uninstall/wipe Transmission again and verify zero-state.
4. Install the exact run #9 4.1.1 APK clean through ADM Manual Install.
5. Verify genuine blank-install behavior: daemon/version/ownership, empty transfer state, WebUI/RPC, and whether ADM shows the prerequisite dialog on a clean Manual Install.
6. Restore the new 4.1.1 backup while stopped and verify all state returns correctly.
7. Investigate the cosmetic `Matt / 4.1.1` maintainer display if it persists or matters after clean install.

Do not delete the two independent Matt 3.00 backups until the full campaign is complete.

## Working rule — mandatory checkpoint discipline

This file is the authoritative compact checkpoint. Update it after every successful code/package change and every successful build, validation or NAS test before that step is considered closed.
