# Transmission for legacy ASUSTOR x86-64

A reproducible, self-contained **Transmission** build and native **ASUSTOR App Central** package for older x86-64 ADM systems.

The project exists for legacy ASUSTOR hardware whose ADM userspace is too old for current App Central builds, while still providing a 64-bit Linux environment capable of running a carefully audited modern Transmission runtime.

## Verified baseline

The current reference baseline is **Transmission 4.1.1 (56442e2929)**. It has been physically validated on an **ASUSTOR AS-608T running ADM 3.5.9.RWM1**, with glibc 2.22.

ADM 3.5 is the final major ADM line for the AS-60 series, and 3.5.9.RWM1 is the final published ADM release for the AS-608T.

Verified live behavior includes:

- clean App Central install from zero-state
- daemon identity `admin:administrators`
- WebUI/RPC on port **9091** and Remote GUI access from LAN
- source-level ASUSTOR RPC default matching the LAN-friendly behavior of Matt's historical package
- private curl/OpenSSL/C++ runtime loading through relocatable `$ORIGIN/../lib`
- certificate-verified HTTPS tracker communication
- no `TR_CURL_SSL_NO_VERIFY=1` workaround
- real peer upload/seeding
- tracker-side identification as `Transmission/4.1.1`
- fully automatic **Matt Transmission 3.00 -> 4.1.1** migration through ADM Manual Install
- preservation of **533 `.torrent` + 533 `.resume`** files and existing settings/state during that migration
- replacement of Matt's modified `start-stop.sh` with the clean 4.1.1 service script during upgrade

The 4.1.1 baseline is therefore considered **functionally complete and physically validated**. The next development step is to port the same proven build/package design to **Transmission 4.1.3 stable** and repeat the same CI and physical NAS validation.

See [`docs/PROJECT-STATE.md`](docs/PROJECT-STATE.md) for the authoritative checkpoint.

## Build target

- Architecture: **x86-64**
- Verified Transmission baseline: **4.1.1**
- Next target: **4.1.3 stable**
- OpenSSL: **3.5.7**
- curl: **8.21.0**
- maximum audited glibc requirement on the verified baseline: **GLIBC_2.17**
- audited C++ requirements: **GLIBCXX_3.4.19**, **CXXABI_1.3.5**
- private runtime: curl, OpenSSL, `libstdc++`, `libgcc_s`, OpenSSL modules and CA trust
- private-library lookup: exact relocatable **`$ORIGIN/../lib`**

The build deliberately does not hard-code `/usr/local/AppCentral/transmission/lib` into the binaries.

## Compatibility

The verified binary compatibility contract for the 4.1.1 baseline is:

```text
ASUSTOR x86-64 + glibc >= 2.17
```

The primary physical target is the **AS-608T**. Other 64-bit AS-6 family systems are expected candidates, including AS-602T, AS-604T, AS-606T, AS-608T, AS-604RS/RD and AS-609RS/RD. Only the AS-608T has been physically validated so far; other models should be treated as expected-compatible rather than confirmed.

This build is not for older 32-bit x86 ASUSTOR models.

## Why the runtime is self-contained

Legacy ADM releases ship old TLS and C++ libraries. This project avoids depending on them by bundling the modern networking, crypto and C++ runtime required by Transmission.

The release tree is audited so that no builder-only paths leak into the runtime, `transmission-daemon --version` runs with `LD_LIBRARY_PATH` unset, private libraries resolve through `$ORIGIN/../lib`, bundled CA trust performs certificate-verified HTTPS, and the staged ELF set remains within the configured ABI floor.

The historical `TR_CURL_SSL_NO_VERIFY=1` workaround is intentionally excluded.

## ASUSTOR package behavior

The workflow builds a native APKG 2.0 container with:

```text
apkg-version
control.tar.gz
data.tar.gz
```

The packaged `config/` directory is intentionally empty. User settings, torrent files, resume files, DHT state, statistics and blocklists are never baked into the APK.

The package retains compatibility-critical behavior from Matt's historical 3.00 package while modernizing the implementation:

- strict POSIX `/bin/sh` lifecycle scripts
- relocatable `$ORIGIN/../lib`
- runtime-derived `TRANSMISSION_WEB_HOME`
- verified TLS with bundled CA trust
- no unconditional legacy UDP sysctl tuning
- migration marker before state restore
- hidden files preserved with `config/.` copy semantics
- clean-install RPC default patched in Transmission source rather than synthesizing `settings.json`

## Build pipeline

The active GitHub Actions workflow validates the standalone runtime, ABI/private-library resolution, verified HTTPS, stripped release tree, APKG payload, native APK structure and lifecycle/migration safety gates.

Important files:

- [`scripts/build-transmission-source-rpc.sh`](scripts/build-transmission-source-rpc.sh) — source build wrapper including the ASUSTOR clean-install RPC default patch
- [`scripts/build-transmission-standalone.sh`](scripts/build-transmission-standalone.sh) — reproducible standalone runtime build
- [`scripts/finalize-transmission-release.sh`](scripts/finalize-transmission-release.sh) — final ELF stripping and sanity checks
- [`scripts/prepare-apkg-payload.sh`](scripts/prepare-apkg-payload.sh) — minimal App Central payload
- [`scripts/build-asustor-apk.sh`](scripts/build-asustor-apk.sh) — native APKG 2.0 packager and package gates
- [`.github/workflows/build.yml`](.github/workflows/build.yml) — canonical CI workflow

## Project documentation

- [`docs/PROJECT-STATE.md`](docs/PROJECT-STATE.md) — authoritative project checkpoint and next step
- [`docs/BUILD-NOTES.md`](docs/BUILD-NOTES.md) — technical build rationale and ABI findings
- [`docs/PACKAGING-HISTORY.md`](docs/PACKAGING-HISTORY.md) — historical ASUSTOR/Transmission package analysis and migration rationale

## Licensing

The build, packaging and CI tooling authored in this repository is released under the **MIT License**; see [`LICENSE`](LICENSE).

Transmission itself is not relicensed by this repository. The generated package contains Transmission and third-party runtime components under their respective upstream licenses. The Transmission license notice shipped inside the APK is maintained separately as `package/CONTROL/license.txt`.
