# Mission Transmission Rebuild — Project State

Last updated: 2026-08-15 11:xx CEST

## Current phase

**Transmission 4.1.1 is now the fully validated reference baseline.**

The next phase is a controlled port to **Transmission 4.1.3 stable**, reusing the proven 4.1.1 build, runtime, APKG and migration design and changing only what the new upstream version requires.

Primary physical target: **ASUSTOR AS-608T**, x86-64, glibc 2.22, **ADM 3.5.9.RWM1**.

ASUSTOR documents ADM 3.5 as the final major ADM line for the AS-60 family and lists ADM 3.5.9.RWM1 (2022-08-29) as the final published ADM release for the AS-608T.

## Frozen 4.1.1 reference baseline — GREEN

- Transmission 4.1.1 (`56442e2929`)
- OpenSSL 3.5.7 / curl 8.21.0
- pinned manylinux2014 build environment
- max audited `GLIBC_2.17`
- `GLIBCXX_3.4.19`, `CXXABI_1.3.5`
- exact relocatable `$ORIGIN/../lib`
- bundled CA trust and certificate-verified HTTPS
- no `TR_CURL_SSL_NO_VERIFY=1`
- native APKG 2.0 package
- clean WebUI and Remote GUI access on port 9091
- real tracker/peer traffic and seeding verified
- external tracker identification as `Transmission/4.1.1`

## Clean-install behavior — PHYSICALLY VALIDATED

A genuine zero-state install of the source-patched 4.1.1 APK was performed through ADM Manual Install.

Observed result:

```text
transmission-daemon 4.1.1 (56442e2929)
```

The daemon started automatically as `admin`, with 0 torrents and 0 resume files. Transmission itself generated `settings.json` and the effective RPC values included:

```text
"rpc-whitelist": "127.0.0.1,::1",
"rpc-whitelist-enabled": false,
```

WebUI opened normally from the LAN and displayed `Transmission 4.1.1 (56442e2929)`. Remote GUI access also worked without manual configuration edits.

### Why the RPC source patch exists

An unpatched clean 4.1.1 install generated an enabled localhost-only RPC whitelist and both WebUI and Remote GUI received HTTP 403 from LAN clients.

A clean official Matt Transmission 3.00 install was then inspected. Its generated settings had the effective final value:

```text
"rpc-whitelist": "127.0.0.1",
"rpc-whitelist-enabled": false,
```

Matt's CONTROL scripts contain no RPC/settings manipulation and opening his WebUI did not change that value. The selected ASUSTOR-compatible solution is therefore a minimal source-level daemon default patch, applied after checkout and before compilation:

```cpp
app_defaults_map.try_emplace(TR_KEY_rpc_whitelist_enabled, false);
```

This changes only the default used when creating fresh settings. It does not modify WebUI assets, torrent/peer/tracker logic or existing/migrated settings.

A temporary design that created a synthetic clean-install `settings.json` from `post-install.sh` was abandoned and removed from `main`.

## Matt 3.00 -> 4.1.1 migration — PHYSICALLY VALIDATED

The final migration test intentionally reproduced the real historical installation state.

1. NAS returned to clean zero-state.
2. Official Matt Transmission 3.00 installed from App Central.
3. Independent historical backup restored while stopped: exactly **533 `.torrent` + 533 `.resume`**.
4. Historical HTTPS workaround added to Matt's service script:

```sh
TR_CURL_SSL_NO_VERIFY=1; export TR_CURL_SSL_NO_VERIFY
```

5. Matt 3.00 started and verified as a working pre-upgrade baseline:

```text
transmission-daemon 3.00 (bb6b5a062e)
533 torrents
533 resume files
```

6. Matt 3.00 was deliberately left running and the source-patched 4.1.1 APK was installed over it through ADM Manual Install, allowing ADM to exercise the real stop/replace/start lifecycle.

Post-upgrade result:

```text
transmission-daemon 4.1.1 (56442e2929)
533 torrents
533 resume files
```

Exactly one Transmission daemon was running. WebUI/Remote GUI and existing torrent state were intact. Tracker behavior looked normal.

Critically, the installed 4.1.1 `CONTROL/start-stop.sh` contained **no** `TR_CURL_SSL_NO_VERIFY`, proving program payload replacement occurred while durable user state was preserved.

**The unattended Matt 3.00 -> 4.1.1 migration path is therefore physically validated on the target AS-608T.**

## Migration compatibility contract

Preserve:

- package ID `transmission`
- config path `/usr/local/AppCentral/transmission/config`
- daemon identity `admin:administrators`
- PID `/var/run/transmission-daemon.pid`
- RPC port 9091
- start-order 20 / stop-order 80
- `start-stop-daemon` service model
- graceful stop + forced-stop fallback
- all settings, torrent metadata, resume data, DHT state, blocklists and statistics

Intentional modernization:

- strict POSIX `/bin/sh`
- relocatable `$ORIGIN/../lib`
- bundled modern curl/OpenSSL/C++ runtime
- bundled CA trust and real certificate validation
- no insecure SSL bypass
- no unconditional historical UDP sysctl tuning
- explicit migration marker
- `config/.` copy semantics preserving hidden files

## Known backups — DO NOT DELETE YET

Independent Matt 3.00 backups:

```text
/volume1/Download/transmission-3.00-full-backup.tar.gz
/volume1/Download/transmission-3.00-config-backup.tar.gz
```

Known-good 4.1.1 backups:

```text
/volume1/Download/transmission-4.1.1-full-backup.tar.gz
/volume1/Download/transmission-4.1.1-config-backup.tar.gz
```

The 4.1.1 config backup passed gzip integrity testing and contains exactly 533 torrent + 533 resume files.

## App Central observations

- Clean Manual Install displays the required Download-share / port-9091 prerequisite flow.
- Unverified-package review correctly shows the package version and maintainer.
- The Installed view can retain stale App Central catalog metadata until App Central is restarted; package runtime behavior is unaffected.
- Final release cleanup must ensure package-owned metadata is complete and internally consistent: maintainer, developer, website, version, description and changelog.
- ADM refuses same-version `4.1.1 -> 4.1.1` Manual Install with Ref. 6001 before lifecycle hooks run.

## Canonical build layout

Only one active workflow is intended on `main`: `.github/workflows/build.yml`.

Canonical scripts:

- `scripts/build-transmission-source-rpc.sh` — source wrapper + ASUSTOR RPC default patch
- `scripts/build-transmission-standalone.sh` — runtime build
- `scripts/finalize-transmission-release.sh` — strip/final validation
- `scripts/prepare-apkg-payload.sh` — minimal payload
- `scripts/build-asustor-apk.sh` — native APKG build and package gates

The old experiment branch was useful for proving the source patch but is no longer part of the design and may be deleted after its useful history is no longer needed.

## Next phase — Transmission 4.1.3

Proceed from this frozen 4.1.1 reference baseline rather than redesigning the package.

1. Review upstream 4.1.1 -> 4.1.3 source/build changes.
2. Change the checkout/version/package metadata to 4.1.3.
3. Verify whether the GCC-10 `is_ipv6_6to4()` compatibility patch is still required and adjust only if upstream changed the relevant code.
4. Reapply/verify the clean-install RPC default patch at the correct 4.1.3 daemon location.
5. Run the normal ABI, RPATH, private-runtime, TLS, stripping, payload and APKG gates.
6. Verify the resulting daemon identity/version and inspect the generated APK before NAS installation.
7. Repeat physical clean-install validation on AS-608T / ADM 3.5.9.RWM1.
8. Repeat a real Matt 3.00 -> new-version migration with the 533/533 state baseline.
9. Perform final App Central metadata/changelog cleanup and create the tagged release only after the 4.1.3 physical tests pass.

## Workflow/session discipline

- GitHub is the persistent project record.
- Fetch a failed Actions log **once per failed run**, analyze that fetched result, and do not repeatedly download the same log.
- `PROJECT-STATE.md` is the compact authoritative checkpoint.
- `BUILD-NOTES.md` records deeper technical rationale.
- `PACKAGING-HISTORY.md` records historical package findings.
