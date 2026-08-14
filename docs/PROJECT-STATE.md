# Mission Transmission Rebuild — Project State

Last updated: 2026-08-14 22:58 CEST

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
- Download Center's separate root `transmissiond` remains untouched
- WebUI/Remote GUI works on 9091
- **533 `.torrent` + 533 `.resume`** restored
- WebUI shows **533 Transfers**
- HTTPS tracker communication works
- real peer upload/seeding observed from restored state
- external tracker profile identifies `Transmission/4.1.1` and showed 116 currently seeding

Exact untouched independent backups:

```text
/volume1/Download/transmission-3.00-full-backup.tar.gz
/volume1/Download/transmission-3.00-config-backup.tar.gz
```

The empty post-install diagnostic config is preserved as:

```text
/usr/local/AppCentral/transmission/config.empty-4.1.1
```

## Automatic migration bug — ROOT CAUSE CLASS IDENTIFIED

The first successful old-ADM Manual Install replaced Matt 3.00 with 4.1.1 but produced empty `torrents/` and `resume/` directories. Our lifecycle scripts treated `APKG_PKG_STATUS=install` as an unconditional clean install and only protected state for `upgrade`.

Observed Manual Install behavior proves that assumption is unsafe on this ADM generation. The package replacement can occur through the `install` lifecycle path.

Do not claim the exact ADM environment value is independently logged yet; the fix is intentionally status-robust instead of depending on that unproven detail.

## Migration hardening + repo cleanup — CODE CHANGED, CI REQUIRED

Commit:

```text
ffd4b5c3cf1508404968cc2d05405518c9c0d225
```

Changes:

- `pre-install.sh` now treats `install` as clean only when no real existing Transmission state is detected; existing config/root-state is backed up exactly like an upgrade.
- `post-install.sh` restores a completed backup marker for both `install` and `upgrade`; `upgrade` still fails closed if its required marker/temp environment is missing.
- `scripts/build-asustor-apk.sh` now runs a lifecycle regression test that simulates an **install-labelled replacement with existing settings/torrent/resume state** and a true clean install.
- `README.md` rewritten around the real current build, native APK and live NAS validation status.
- root `LICENSE` added: repository-authored build/packaging/CI tooling is MIT-licensed; Transmission and bundled third-party components retain their upstream licenses.

## Mandatory next step

1. Wait for the workflow triggered by `ffd4b5c3...`.
2. Require the lifecycle regression, payload/package gates and full native APK build to pass.
3. Inspect the resulting APK physically.
4. Update this checkpoint with run ID/artifact/hash/result.
5. Revalidate the hardened lifecycle on the NAS before calling unattended Manual Install migration release-ready.

## Repository presentation

README and licensing are now populated. GitHub repository metadata currently has no About description/topics configured. The connected GitHub tool does not expose repository-metadata mutation, so About text/topics must be set through GitHub UI unless that capability becomes available.

Suggested About description:

```text
Transmission 4.1.1 for legacy ASUSTOR x86-64/ADM — self-contained glibc 2.17 build and native App Central package.
```

Suggested topics: `asustor`, `transmission`, `bittorrent`, `adm`, `nas`, `x86-64`, `legacy-linux`.

## Working rule — mandatory checkpoint discipline

This file is the authoritative compact checkpoint. Update it after every successful code/package change and every successful build, validation or NAS test before that step is considered closed.
