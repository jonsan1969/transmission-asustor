# Transmission 4.1.1 for legacy ASUSTOR x86-64

A reproducible, self-contained **Transmission 4.1.1** build and native **ASUSTOR App Central** package for older x86-64 ADM systems.

The project targets legacy hardware that still has a sufficiently new 64-bit Linux userspace but can no longer use current App Central builds because the system libraries are too old.

## Current status

The runtime and native APK have been physically validated on an **ASUSTOR AS-608T** running legacy ADM with glibc 2.22.

Verified live behavior includes:

- Transmission **4.1.1 (56442e2929)** running from `/usr/local/AppCentral/transmission`
- daemon identity `admin:administrators`
- WebUI/RPC on port **9091**
- Remote GUI compatibility
- private curl/OpenSSL/C++ runtime loading through relocatable `$ORIGIN/../lib`
- certificate-verified HTTPS tracker communication
- restored legacy torrent/resume state
- real peer upload/seeding from restored torrents
- tracker-side identification as `Transmission/4.1.1`
- coexistence with ASUSTOR Download Center's separate Transmission-derived daemon

### Upgrade migration status

The package installs successfully over the historical Matt Transmission 3.00 package, but the first real **ADM Manual Install** replacement exposed an important old-ADM lifecycle quirk: the operation did not automatically restore the existing 3.00 state because the package hooks assumed `APKG_PKG_STATUS=upgrade`.

The lifecycle logic is being hardened so an existing Transmission state is detected and protected even when old ADM labels a manual replacement as `install`.

Until that corrected path has been revalidated, treat the project as **tested but not yet release-final for unattended 3.00 -> 4.1.1 migration**.

See [`docs/PROJECT-STATE.md`](docs/PROJECT-STATE.md) for the authoritative current checkpoint.

## Build target

- Architecture: **x86-64**
- Transmission: **4.1.1**
- OpenSSL: **3.5.7**
- curl: **8.21.0**
- maximum audited glibc requirement: **GLIBC_2.17**
- audited C++ requirements: **GLIBCXX_3.4.19**, **CXXABI_1.3.5**
- private runtime: curl, OpenSSL, `libstdc++`, `libgcc_s`, OpenSSL modules and CA trust
- private-library lookup: exact relocatable **`$ORIGIN/../lib`**

The build deliberately does **not** hard-code `/usr/local/AppCentral/transmission/lib` into the binaries.

## Compatibility

The binary compatibility contract is:

```text
ASUSTOR x86-64 + glibc >= 2.17
```

The primary physical target is the **AS-608T**. Other 64-bit AS-6 family systems are expected candidates, including:

- AS-602T
- AS-604T
- AS-606T
- AS-608T
- AS-604RS / AS-604RD
- AS-609RS / AS-609RD

Only the AS-608T has been physically validated so far. Other models should be treated as expected compatible until tested.

This build is **not** for older 32-bit x86 ASUSTOR models.

## Why the runtime is self-contained

Legacy ADM releases ship old TLS and C++ libraries. This project avoids depending on them by bundling the modern networking, crypto and C++ runtime needed by Transmission 4.1.1.

The final bundle is audited so that:

- no builder-only `/opt/transmission-deps` paths leak into the runtime
- `transmission-daemon --version` runs with `LD_LIBRARY_PATH` unset
- Transmission executables resolve their private libraries through `$ORIGIN/../lib`
- bundled CA trust performs certificate-verified HTTPS
- the staged ELF set stays within the configured ABI floor

The old package's insecure `TR_CURL_SSL_NO_VERIFY=1` workaround is intentionally **not** carried forward.

## Native ASUSTOR package

The workflow builds a real APKG 2.0 container with exactly:

```text
apkg-version
control.tar.gz
data.tar.gz
```

The packaged user `config/` directory is intentionally empty. Existing settings, torrent files, resume files, DHT state, statistics and blocklists must come from the installed package during an upgrade; they are never baked into the APK.

The package keeps the compatibility-critical behavior of Matt's historical 3.00 package while deliberately improving several implementation details:

- real POSIX `/bin/sh` lifecycle scripts; no Bash `[[ ... ]]`
- relocatable `$ORIGIN/../lib` instead of absolute RPATH
- runtime-derived `TRANSMISSION_WEB_HOME`
- certificate verification enabled
- no unconditional historical UDP sysctl tuning
- explicit migration marker before restore
- hidden files preserved with `config/.` copy semantics

## Build pipeline

The active GitHub Actions workflow builds and validates:

1. the standalone Transmission runtime
2. ABI and private-library resolution
3. certificate-verified HTTPS
4. the stripped release tree
5. the minimal APKG payload
6. the native ASUSTOR APK
7. CONTROL/data separation and lifecycle safety gates

Important files:

- [`scripts/build-transmission-standalone.sh`](scripts/build-transmission-standalone.sh) — reproducible Transmission/runtime build
- [`scripts/finalize-transmission-release.sh`](scripts/finalize-transmission-release.sh) — final ELF stripping and sanity checks
- [`scripts/prepare-apkg-payload.sh`](scripts/prepare-apkg-payload.sh) — minimal App Central payload
- [`scripts/build-asustor-apk.sh`](scripts/build-asustor-apk.sh) — native APKG 2.0 packager and package gates
- [`.github/workflows/build.yml`](.github/workflows/build.yml) — CI workflow

## Project documentation

- [`docs/PROJECT-STATE.md`](docs/PROJECT-STATE.md) — authoritative current state, evidence and exact next step
- [`docs/BUILD-NOTES.md`](docs/BUILD-NOTES.md) — technical build rationale and ABI findings
- [`docs/PACKAGING-HISTORY.md`](docs/PACKAGING-HISTORY.md) — historical ASUSTOR/Transmission package analysis

## Licensing

The build, packaging and CI tooling authored in this repository is released under the **MIT License**; see [`LICENSE`](LICENSE).

Transmission itself is **not relicensed by this repository**. The generated package contains Transmission and third-party runtime components under their respective upstream licenses. The Transmission license notice shipped inside the APK is maintained separately as `package/CONTROL/license.txt`.
