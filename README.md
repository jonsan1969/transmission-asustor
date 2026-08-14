# transmission-asustor

Modern **Transmission 4.1.1** build for **ASUSTOR x86-64 NAS** systems, with an intentionally old Linux ABI baseline for legacy ADM hardware.

## Build target

- Architecture: **x86-64**
- Maximum required glibc from the audited bundle: **GLIBC_2.17**
- Transmission: **4.1.1**
- OpenSSL: **3.5.7**
- curl: **8.21.0**
- Private runtime: curl, OpenSSL, `libstdc++`, `libgcc_s` and bundled CA trust
- Relocatable private-library lookup via `$ORIGIN/../lib`

The GitHub Actions artifact is named:

```text
transmission-4.1.1-asustor-x86_64-glibc217
```

## Compatibility

The technical compatibility contract is:

```text
ASUSTOR x86-64 + glibc >= 2.17
```

The project was created for the legacy **AS-6 series**, whose desktop and rack models use a 64-bit Intel Atom platform. The first live validation target is an **AS-608T** running ADM with glibc 2.22.

Expected AS-6 family candidates include:

- AS-602T
- AS-604T
- AS-606T
- AS-608T
- AS-604RS / AS-604RD
- AS-609RS / AS-609RD

These models should be treated as **expected compatible until physically tested**. Newer ASUSTOR x86-64 models with a sufficiently new glibc should also satisfy the binary ABI requirement, but App Central package integration may still vary by ADM generation.

The build is **not** for older 32-bit x86 ASUSTOR models such as the AS-2 / AS-3 generation.

## Build status

The current build pipeline verifies all of the following before publishing the artifact:

- Transmission 4.1.1 compiles successfully with GCC 10 / C++17
- staged binaries use the private bundle rather than the builder prefix
- staged `curl` and `transmission-daemon` use relocatable `$ORIGIN/../lib` lookup
- no `/opt/transmission-deps` runtime dependency leaks into the final bundle
- bundled CA trust performs a real certificate-verified HTTPS request
- `transmission-daemon --version` runs with `LD_LIBRARY_PATH` unset
- all staged ELF files pass the configured ABI audit

The Transmission executables currently audit at:

```text
GLIBC_2.17
GLIBCXX_3.4.19
CXXABI_1.3.5
```

The supplied private GCC runtime keeps the bundle independent of an old ADM `libstdc++`.

## Build strategy

The bundle is intentionally self-contained instead of relying on ADM's old SSL/C++ stack. It includes private networking, crypto and C++ runtime libraries plus CA trust and uses a small wrapper for the bundled TLS environment.

Historical probe workflows used to establish the toolchain and ABI strategy have been removed from the active Actions list now that the build is reproducible. Their commits and results remain available in Git history and in `docs/BUILD-NOTES.md`.

## NAS validation

The standalone artifact must be tested in a **separate directory** before the installed App Central package is touched. Initial validation should include:

1. `file` and program-interpreter inspection
2. `ldd` / resolved-library verification
3. `transmission-daemon --version`
4. isolated daemon startup with a temporary config and non-conflicting ports
5. HTTPS/TLS verification

Only after that should an ASUSTOR `.apk` upgrade package be produced.

## Packaging and existing data

Matt's original App Central package layout and CONTROL scripts are retained under `package/` as a compatibility reference.

An eventual upgrade must preserve the existing Transmission configuration and state, including settings, `.torrent` files, resume data, DHT state, blocklists and statistics.

The currently installed AS-608T package had previously been modified locally with:

```sh
TR_CURL_SSL_NO_VERIFY=1; export TR_CURL_SSL_NO_VERIFY
```

That workaround is **not** part of this rebuild. The new bundle uses proper certificate verification with bundled CA trust.

## Project notes

- `docs/PROJECT-STATE.md` — compact current checkpoint and next step
- `docs/BUILD-NOTES.md` — durable technical findings and build rationale
- `scripts/build-transmission-standalone.sh` — reproducible bundle build and audit
- `.github/workflows/build.yml` — active GitHub Actions build
