# Mission Transmission Rebuild — Project State

Last updated: 2026-08-15 07:10 CEST

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

## Migration hardening — CI GREEN

Migration hardening commit:

```text
ffd4b5c3cf1508404968cc2d05405518c9c0d225
```

CI test-harness fix:

```text
b2ce9394f2fade97cbdbaeab9485c3875592a252
```

Changes now covered:

- `pre-install.sh` treats `install` as clean only when no real existing Transmission state is detected; existing config/root-state is backed up exactly like an upgrade.
- `post-install.sh` restores a completed backup marker for both `install` and `upgrade`; `upgrade` still fails closed if its required marker/temp environment is missing.
- `scripts/build-asustor-apk.sh` runs a lifecycle regression that simulates an **install-labelled replacement with existing settings/torrent/resume state** plus a true clean install.
- CI uses a test-only `chown` shim so Ubuntu can execute the lifecycle regression while separately asserting that the packaged NAS hook still contains `chown -R admin:administrators`.

GitHub Actions **run #9 / run ID 31865580032** completed successfully on commit `b2ce9394f2fade97cbdbaeab9485c3875592a252`.

Native APK artifact:

```text
Artifact ID: 9241979173
Artifact name: transmission-4.1.1-asustor-x86_64-apk
APK filename: transmission_4.1.1_x86-64.apk
APK size: 11918683 bytes
APK SHA-256: dfa339d4eb2f7e9509a6d776b58fbfb8bf82f6424a841efa188e86d176702f6c
```

Physical inspection of the downloaded APK passed:

- top-level members exactly `apkg-version`, `control.tar.gz`, `data.tar.gz`
- `apkg-version` = `2.0`
- CONTROL contains config, description, changelog, license, three 90x90 icon assets and all three lifecycle hooks
- `pre-install.sh`, `post-install.sh`, `start-stop.sh` retain executable mode
- data payload contains `bin`, `lib`, `share`, and an intentionally empty `config/`
- no torrent/resume/settings state is shipped in the package
- packaged migration hooks contain `has_existing_state` and `.apkg-backup-complete` handling
- post-install handles both `install|upgrade`
- packaged NAS ownership remains `admin:administrators`

## Mandatory next step

Revalidate the hardened lifecycle **physically on the AS-608T** using ADM Manual Install before calling unattended migration release-ready.

The acceptance test is that installing the run #9 APK over the currently working Transmission installation preserves the existing config and all torrent/resume state automatically, without manual restore or SSH repair. After installation verify at minimum:

1. App Central still reports Transmission 4.1.1.
2. daemon starts as `admin` from `/usr/local/AppCentral/transmission/bin/transmission-daemon`.
3. `settings.json`, `torrents/`, and `resume/` survive unchanged.
4. torrent/resume counts remain 533/533 unless legitimate torrent activity changed them before the test.
5. WebUI/Remote GUI loads the existing transfer list.
6. Download Center's separate root `transmissiond` remains untouched.
7. tracker communication and at least one real transfer/upload still work.

Do not delete the two independent Matt 3.00 backups until this physical migration test is complete.

## Repository presentation

README and licensing are populated. Suggested About description:

```text
Transmission 4.1.1 for legacy ASUSTOR x86-64/ADM — self-contained glibc 2.17 build and native App Central package.
```

Suggested topics: `asustor`, `transmission`, `bittorrent`, `adm`, `nas`, `x86-64`, `legacy-linux`.

## Working rule — mandatory checkpoint discipline

This file is the authoritative compact checkpoint. Update it after every successful code/package change and every successful build, validation or NAS test before that step is considered closed.
