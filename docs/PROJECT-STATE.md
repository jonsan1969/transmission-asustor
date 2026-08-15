# Mission Transmission Rebuild — Project State

Last updated: 2026-08-15 14:xx CEST

## Current phase

**Transmission 4.1.1 is RELEASED, physically validated and running in production on the reference NAS.**

The next phase is a controlled port to **Transmission 4.1.3 stable**, reusing the proven 4.1.1 build, runtime, APKG and migration design and changing only what the new upstream version requires.

Primary physical target: **ASUSTOR AS-608T**, x86-64, glibc 2.22, **ADM 3.5.9.RWM1**.

ASUSTOR documents ADM 3.5 as the final major ADM line for the AS-60 family and lists ADM 3.5.9.RWM1 (2022-08-29) as the final published ADM release for the AS-608T.

## Frozen 4.1.1 reference baseline — RELEASED / GREEN / PRODUCTION

- Transmission 4.1.1 (`56442e2929`)
- OpenSSL 3.5.7 / curl 8.21.0
- pinned manylinux2014 build environment
- max audited `GLIBC_2.17`
- `GLIBCXX_3.4.19`, `CXXABI_1.3.5`
- exact relocatable `$ORIGIN/../lib`
- bundled CA trust and certificate-verified HTTPS
- native APKG 2.0 package
- clean WebUI and Remote GUI access on port 9091
- real tracker/peer traffic and seeding verified
- tracker-side identification as `Transmission/4.1.1`, built from upstream revision `56442e2929`
- public GitHub release created with the final APK
- final release APK reinstalled on the reference NAS and the known-good 4.1.1 config/state restored successfully

Current production verification after restore:

```text
transmission-daemon 4.1.1 (56442e2929)
```

Exactly one daemon is running as `admin` using `/usr/local/AppCentral/transmission/config`. The restored state contains 533 `.torrent` and 533 `.resume` files; these counts are retained here as a test record, not as a product requirement.

**Do not modify the released 4.1.1 baseline for 4.1.3 development. Treat it as the known-good rollback/reference point.**

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

### WebUI cache after switching versions

During the final production restore, the browser initially displayed a partially broken 4.1.1 inspector UI: the tab controls were present but their labels were blank. The daemon, restored state and other WebUI data were otherwise correct.

This was confirmed to be stale browser assets cached from the immediately preceding Transmission 3.00 test installation. A hard refresh (`Ctrl+F5`) loaded the current 4.1.1 WebUI assets and restored the UI completely.

**Testing note:** after switching between substantially different Transmission WebUI versions on the same NAS URL (especially 3.00 -> 4.1.x), perform a hard browser refresh before diagnosing apparent WebUI rendering defects. This is a client-cache issue, not an APKG/config migration failure.

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
4. A historical HTTPS workaround was added manually for this test to the installed 3.00 service script:

```sh
TR_CURL_SSL_NO_VERIFY=1; export TR_CURL_SSL_NO_VERIFY
```

This workaround was **not part of Matt's original package** and must not be described as such.

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

Critically, the installed 4.1.1 `CONTROL/start-stop.sh` contained no `TR_CURL_SSL_NO_VERIFY`, proving program payload replacement occurred while durable user state was preserved.

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
- no insecure SSL bypass in the released package
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

Both 4.1.1 archives passed gzip integrity testing. The config backup was used successfully to restore production state after installing the final published 4.1.1 release APK.

## Final App Central metadata / presentation findings

Package-owned metadata is now intentionally minimal and release-ready:

- Maintainer: `Jonas Sandberg`
- no `email` field in `config.json`
- Website: project GitHub repository
- short App Central description
- changelog is plain text plus the official upstream Transmission release URL, because legacy ADM does not render Markdown link syntax cleanly

Legacy ADM still displays a `mailto:` action when hovering/clicking the maintainer name even when the APK contains no `email` field. This appears to be ADM UI behavior and is not worked around in the package.

The Installed view also displays historical ASUSTOR App Central catalog data below the package version, including old size/download/date/screenshot information. This appears to be server-side/catalog metadata associated with package ID `transmission`, not metadata supplied by the locally installed APK. Do not try to encode fake replacement values into the package.

The three legacy ADM icons are now vendored in the repository:

```text
package/CONTROL/icon.png
package/CONTROL/icon-enable.png
package/CONTROL/icon-disable.png
```

The build no longer downloads Matt's old 3.00 APK from ASUSTOR to obtain them. The build verifies the vendored icons by expected SHA-256 and 90x90 PNG dimensions. This removes an unnecessary long-term dependency on the historical App Central download URL.

Known verified icon hashes:

```text
icon.png / icon-enable.png:
9b08828efa4b7cae7e8329038b363aec397738060f973081898b5ce65b4e7690

icon-disable.png:
fcc419d0b67c8cea0808c9a696af037067e796e298122ca0b8a3cb52608030b3
```

## Release packaging policy

GitHub Actions may retain standalone bundles, APKG payloads and diagnostic/check artifacts for CI/debugging.

Public GitHub releases should stay minimal:

- native `transmission_<version>_x86-64.apk`
- GitHub-generated source archives

Do not publish CI check files or intermediate payload/build artifacts as release assets unless there is a specific debugging reason.

## Canonical build layout

Only one active workflow is intended on `main`: `.github/workflows/build.yml`.

Canonical scripts:

- `scripts/build-transmission-source-rpc.sh` — source wrapper + ASUSTOR RPC default patch
- `scripts/build-transmission-standalone.sh` — runtime build
- `scripts/finalize-transmission-release.sh` — strip/final validation
- `scripts/prepare-apkg-payload.sh` — minimal payload
- `scripts/build-asustor-apk.sh` — native APKG build and package gates

The temporary experiment branch used to prove the RPC source patch has been deleted. Old probe/test workflow runs were cleaned up; the retained workflow history should be treated only as CI history, not project state.

## Next phase — Transmission 4.1.3

Proceed from this frozen 4.1.1 reference baseline rather than redesigning the package.

1. Review upstream 4.1.1 -> 4.1.3 source/build changes and release notes before changing code.
2. Change checkout/version/package metadata to 4.1.3.
3. Record and verify the exact upstream 4.1.3 revision reported by the built daemon.
4. Verify whether the GCC-10 `is_ipv6_6to4()` compatibility patch is still required and adjust only if upstream changed the relevant code.
5. Reapply/verify the clean-install RPC default patch at the correct 4.1.3 daemon location; do not assume the 4.1.1 source location/context is unchanged.
6. Run the normal ABI, RPATH, private-runtime, TLS, stripping, payload, icon and APKG gates.
7. Verify the resulting daemon identity/version and inspect the generated APK before NAS installation.
8. Repeat physical zero-state clean-install validation on AS-608T / ADM 3.5.9.RWM1, including WebUI and Remote GUI from LAN with no manual settings edit. Hard-refresh the browser after version switches before treating WebUI rendering anomalies as package defects.
9. Repeat a real Matt 3.00 -> 4.1.3 migration using the preserved historical backup/state baseline and verify service-script replacement plus state preservation.
10. Test real HTTPS tracker communication and peer upload/seeding and verify tracker/client identification for 4.1.3.
11. Update README, PROJECT-STATE, App Central description/changelog and release notes to 4.1.3 only after physical validation succeeds.
12. Create the tagged GitHub 4.1.3 release from the final green build; keep 4.1.1 untouched as rollback/reference.

## Distribution after 4.1.3

Two distribution paths should be pursued after 4.1.3 is physically validated and released:

1. **ASUSTOR App Central:** investigate whether ASUSTOR will accept a community-maintained update/revival of the legacy native Transmission package for EOL x86-64/ADM hardware. Do not assume ownership of Matt's existing catalog/package entry can be transferred; ask ASUSTOR explicitly.
2. **ASUSTOR Community Forum:** publish a Transmission forum post linking to the GitHub project/release so legacy-ASUSTOR users searching for a newer Transmission build can find it even if official App Central publication is unavailable.

The forum route remains useful regardless of ASUSTOR's App Central decision.

## New-thread handoff

For a fresh conversation, start from this file and treat the following as non-negotiable known-good facts:

- 4.1.1 is released and currently running in production on the AS-608T.
- The exact verified daemon is `Transmission 4.1.1 (56442e2929)`.
- The final 4.1.1 APK has been installed from the public release and production config/state restored successfully.
- Do not redesign the package for 4.1.3; port the frozen design.
- Preserve the source-level RPC default patch behavior (`rpc-whitelist-enabled = false`) for clean installs, after verifying the 4.1.3 source location.
- Preserve package ID/path/service/migration compatibility with Matt 3.00.
- Keep TLS certificate verification; never reintroduce `TR_CURL_SSL_NO_VERIFY` into the package.
- Keep the vendored legacy ADM icons and their integrity checks.
- Remember that stale browser-cached WebUI assets can survive a 3.00/4.1.x version switch; hard-refresh before debugging UI rendering.
- Keep the four NAS backups until 4.1.3 clean-install and migration testing are complete.
- After 4.1.3 release, pursue App Central publication and an ASUSTOR Community Forum announcement.

## Workflow/session discipline

- GitHub is the persistent project record.
- Fetch a failed Actions log **once per failed run**, analyze that fetched result, and do not repeatedly download the same log.
- `PROJECT-STATE.md` is the compact authoritative checkpoint.
- `BUILD-NOTES.md` records deeper technical rationale.
- `PACKAGING-HISTORY.md` records historical package findings.
