# Mission Transmission Rebuild — Project State

Last updated: 2026-08-15 10:xx CEST

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
- WebUI/Remote GUI works on 9091 when RPC whitelist permits LAN access
- initial recovery had **533 `.torrent` + 533 `.resume`**; later live baseline reached **534/534** through legitimate torrent activity
- HTTPS tracker communication works
- real peer upload/seeding observed from restored state
- external tracker profile identifies `Transmission/4.1.1`

Exact untouched independent Matt 3.00 backups:

```text
/volume1/Download/transmission-3.00-full-backup.tar.gz
/volume1/Download/transmission-3.00-config-backup.tar.gz
```

Known-good 4.1.1 backups created after the successful migration:

```text
/volume1/Download/transmission-4.1.1-full-backup.tar.gz
/volume1/Download/transmission-4.1.1-config-backup.tar.gz
```

The 4.1.1 config backup was integrity-tested and contains exactly **533 `.torrent` + 533 `.resume`** files.

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

## Clean-install RPC behavior — ROOT CAUSE VERIFIED

A genuine zero-state 4.1.1 Manual Install was physically tested. The package installed and daemon started correctly as 4.1.1 with **0 torrents / 0 resume files**, but both Remote GUI and browser WebUI received **HTTP 403 Forbidden**.

The newly generated 4.1.1 config showed:

```text
"rpc-bind-address": "0.0.0.0",
"rpc-whitelist": "127.0.0.1,::1",
"rpc-whitelist-enabled": true,
```

Therefore the clean package itself was healthy; upstream 4.1.1's RPC whitelist default prevented LAN clients from reaching the daemon.

A fresh official Matt Transmission 3.00 install was then performed from App Central and inspected before any configuration restore. Its clean `settings.json` contained an effective final value:

```text
"rpc-whitelist": "127.0.0.1",
"rpc-whitelist-enabled": false,
```

The Matt `CONTROL` scripts contain no `settings.json`, RPC or whitelist manipulation. Opening Matt's WebUI did not change these values. This proves the LAN-friendly behavior is produced by the Matt 3.00 build/runtime rather than by his APKG lifecycle scripts.

Upstream Transmission has historically used an enabled RPC whitelist, so the working hypothesis is that Matt compiled his ASUSTOR Transmission with a modified daemon default.

## Final clean-install strategy — SOURCE PATCH, not generated settings.json

A temporary implementation that created a minimal clean-install `settings.json` with `rpc-whitelist-enabled=false` was deliberately abandoned. Commit `ff86a78` and all later commits on that line were removed from `main`; `main` was reset to its parent `055a7e4` before implementing the source-level solution.

The selected approach patches Transmission 4.1.1 source **after the official 4.1.1 checkout and before compilation** by adding:

```cpp
app_defaults_map.try_emplace(TR_KEY_rpc_whitelist_enabled, false);
```

next to the daemon's compiled RPC defaults in `daemon/daemon.cc`.

Scope of the patch:

- changes only the daemon's default used when creating a fresh configuration
- does not modify WebUI assets
- does not modify torrent, peer, tracker, DHT, PEX or µTP logic
- does not overwrite or reinterpret existing/migrated `settings.json`
- avoids APKG `post-install.sh` creating a synthetic configuration file

The isolated experiment already proved that a source-patched build still reports exactly:

```text
transmission-daemon 4.1.1 (56442e2929)
```

The experiment branch's later red CI runs were caused by branch-specific APK/test-harness plumbing, not by the Transmission source patch itself. For that reason the source patch has now been moved to the normal `main` build path and the branch-specific APK machinery is not part of the release design.

## App Central observations

ADM refuses a same-version `4.1.1 -> 4.1.1` Manual Install before lifecycle execution with:

```text
The same version of this App has already been installed. (Ref. 6001)
```

A clean App Central catalog install of Matt 3.00 displays the legacy prerequisite dialog showing required `Download` share, port 9091 and optional port-forwarding checkbox.

A clean 4.1.1 Manual Install also displayed the prerequisite/review flow correctly. After installation, App Central showed the correct package icon and maintainer, although some descriptive metadata in the Installed view remained stale/legacy ADM information. Restarting App Central corrected at least part of the displayed state. Treat remaining display issues as cosmetic unless runtime behavior is affected.

## Mandatory next steps

1. Build the source-patched 4.1.1 through the **normal `main` workflow**.
2. Require normal ABI, runtime, TLS, APKG and migration gates to stay green.
3. Install the resulting APK from a verified zero-state.
4. Before restoring anything, verify the daemon reports `4.1.1 (56442e2929)`, transfer counts are 0/0, and the generated `settings.json` has effective `rpc-whitelist-enabled=false`.
5. Verify WebUI and Remote GUI work immediately from LAN with no manual edit.
6. Restore the independent 4.1.1 backup while stopped and verify all **533 transfers** and state return correctly.
7. Perform final tracker/peer sanity checking and preserve the resulting known-good package details in this file.

Do not delete the independent 3.00 or 4.1.1 backups until the full campaign is complete.

## Working rule — mandatory checkpoint discipline

This file is the authoritative compact checkpoint. Update it after every successful code/package change and every successful build, validation or NAS test before that step is considered closed.
