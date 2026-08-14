# Mission Transmission Rebuild — Build Notes

This file records technical findings and rationale that should survive chat/session boundaries. Keep `PROJECT-STATE.md` concise; put deeper build details here.

## Target and compatibility model

The goal is not merely to compile Transmission 4.1.1. The produced binaries must actually run on the ASUSTOR AS-608T runtime:

- x86-64
- kernel 3.12.20
- glibc 2.22

The App Central package should remain self-contained enough to avoid relying on obsolete ADM networking/crypto/C++ libraries where practical.

## Build environment decision

ASUSTOR's official ADM 2.0 x86-64 cross-toolchain is retained as an ABI/reference source, but its compiler is too old for modern Transmission C++17 code.

The selected hybrid strategy is therefore:

- preserve an old Linux/glibc baseline;
- use a modern-enough compiler;
- build modern userland dependencies privately;
- bundle required C++ runtime components privately;
- audit every final ELF intended for NAS deployment.

The active environment is pinned manylinux2014 with devtoolset-10 / GCC 10:

```text
quay.io/pypa/manylinux2014_x86_64@sha256:0a42cb7e5f4ba6bbfb8d0a86d1aab0c8876ba9c3be16bd99360ae42bf010ec77
```

Inside the container:

```sh
source /opt/rh/devtoolset-10/enable
```

Common compiler flags:

```text
CFLAGS=-O2 -march=x86-64 -mtune=generic
CXXFLAGS=-O2 -march=x86-64 -mtune=generic
```

Private dependency prefix during the probe:

```text
/opt/transmission-deps
```

## OpenSSL 3.5.7

OpenSSL is built from upstream release source with shared libraries and without tests/docs:

```text
./Configure linux-x86_64 shared no-tests no-docs
```

The manylinux2014 image required these extra Perl packages for the selected OpenSSL release:

- `perl-IPC-Cmd`
- `perl-Time-Piece`

Both are smoke-tested before the OpenSSL build.

A prior probe also showed that freshly built OpenSSL tools could not locate their new private runtime libraries. The workflow therefore includes both `$PREFIX/lib64` and `$PREFIX/lib` in `LD_LIBRARY_PATH` during the build.

Historical fixes:

- `0ad89aa274c087fc8b485a1192ad7fe6b4bb7de9` — install OpenSSL Time::Piece dependency
- `0ddf142f09c9def5c1589e1689d7123d3a064cfc` — fix private OpenSSL runtime lookup

## curl 8.21.0

curl is built against the private OpenSSL prefix with a deliberately reduced initial dependency set.

Disabled/omitted for the probe:

- LDAP/LDAPS
- libpsl
- zlib
- brotli
- zstd
- libidn2
- nghttp2/nghttp3
- ngtcp2
- libssh2

The immediate purpose is a small, controllable HTTPS-capable libcurl suitable for Transmission. Optional features can be revisited after NAS runtime validation.

## Transmission 4.1.1 configuration

Current probe profile:

```text
CMAKE_BUILD_TYPE=Release
CMAKE_C_STANDARD=11
CMAKE_CXX_STANDARD=17
ENABLE_DAEMON=ON
ENABLE_CLI=ON
ENABLE_UTILS=ON
ENABLE_GTK=OFF
ENABLE_QT=OFF
ENABLE_MAC=OFF
ENABLE_TESTS=OFF
ENABLE_NLS=OFF
INSTALL_DOC=OFF
INSTALL_LIB=OFF
REBUILD_WEB=OFF
INSTALL_WEB=ON
WITH_SYSTEMD=OFF
WITH_CRYPTO=openssl
```

Private curl and OpenSSL paths are explicitly passed to CMake.

Commit `016c3df27df5732ce2ea67d19eecf2ae5ed5d1f5` extended the configuration probe into actual Transmission compilation plus ELF auditing.

## GCC 10 vs Transmission 4.1.1: `is_ipv6_6to4()`

Initial `libtransmission` compilation failed in `libtransmission/net.h` because upstream 4.1.1 declares this method `constexpr` while the old glibc `htons()` implementation expands through code GCC 10 rejects in a constexpr function.

Upstream form:

```cpp
[[nodiscard]] constexpr bool is_ipv6_6to4() const noexcept
{
    return is_ipv6() && reinterpret_cast<uint16_t const*>(&addr.addr6)[0] == htons(0x2002U);
}
```

Observed compiler error included:

```text
error: uninitialized variable '__v' in 'constexpr' function
```

Chosen workaround: remove `constexpr` from this one method only. The workflow first verifies the expected signature and then patches it, so an upstream source change fails loudly instead of silently editing the wrong code.

Commit:

`0a751f7da64ac618acfbd565eb5823e06eed8db9` — Fix Transmission 4.1.1 GCC 10 constexpr build failure

GitHub Actions run #7 then compiled Transmission successfully and executed `transmission-daemon --version` successfully inside the builder.

## ABI audit philosophy

Passing compilation is only the first gate. For every Transmission executable and every private shared dependency intended for the final bundle inspect:

1. ELF architecture/type (`file`)
2. program interpreter (`readelf -l`)
3. runtime dependencies (`readelf -d`, `NEEDED`)
4. `RPATH` / `RUNPATH`
5. highest required `GLIBC_*`
6. highest required `GLIBCXX_*`
7. highest required `CXXABI_*`

The AS-608T has glibc 2.22. Any deliverable ELF requiring GLIBC newer than 2.22 is an automatic failure.

C++ runtime requirements are handled differently: record GLIBCXX/CXXABI requirements and satisfy them deliberately by shipping a compatible private `libstdc++.so.6`/`libgcc_s.so.1` rather than assuming ADM's versions are sufficient.

## Hard ABI gate added — 2026-08-14

The initial audit printed symbol floors only to the Actions log, meaning a green build did not by itself prove AS-608T compatibility.

The Build Probe was hardened in commit:

`0af2fb935a5c03b04f42c7b8a51c0dd6c7898fee` — Gate ABI audit at GLIBC 2.22 and upload report

The workflow now:

- sets `TARGET_GLIBC=2.22`;
- audits each generated Transmission executable and selected private shared dependency;
- fails if any audited ELF requires a GLIBC symbol newer than 2.22;
- records GLIBCXX/CXXABI maxima diagnostically;
- writes `abi-audit.txt`;
- uploads it as Actions artifact `transmission-abi-audit` even when the build/audit step fails.

Commit `d0aa327d8ce54a66d4b371f50fe22891d1593d1e` additionally enables a push trigger limited to changes of the probe workflow itself, while retaining manual `workflow_dispatch`.

## ABI result — GitHub Actions run #8

Run ID:

```text
31774327556
```

Head commit:

```text
d0aa327d8ce54a66d4b371f50fe22891d1593d1e
```

Result: **success**, including the hard GLIBC gate and ABI artifact upload.

All six Transmission executables reported exactly:

```text
max GLIBC:   GLIBC_2.17
max GLIBCXX: GLIBCXX_3.4.19
max CXXABI:  CXXABI_1.3.5
```

Executables:

- `transmission-cli`
- `transmission-daemon`
- `transmission-create`
- `transmission-edit`
- `transmission-remote`
- `transmission-show`

Private dependency results:

```text
libcrypto.so.3   max GLIBC_2.17
libssl.so.3      max GLIBC_2.17
libcurl.so.4.8.0 max GLIBC_2.17
```

Thus the current compiler/dependency strategy has a comfortable GLIBC margin against the NAS target: generated code requires at most GLIBC 2.17 while the AS-608T provides GLIBC 2.22.

The report artifact for this run is named:

```text
transmission-abi-audit
```

## Runtime dependencies exposed by the successful audit

The Transmission executables currently declare these important `NEEDED` entries:

```text
libcurl.so.4
libssl.so.3
libcrypto.so.3
libstdc++.so.6
libgcc_s.so.1
libpthread.so.0
libm.so.6
libc.so.6
```

The first five require deliberate bundle/runtime treatment. Normal glibc-family libraries should remain system-provided unless NAS testing proves otherwise.

The generated Transmission executables currently contain this build-only RPATH:

```text
/opt/transmission-deps/lib:/opt/transmission-deps/lib64:
```

This is unsuitable for the NAS and is the next packaging issue to solve.

## Standalone bundle design requirements

Before creating an ASUSTOR package, produce a standalone test artifact with a layout conceptually like:

```text
transmission-standalone/
  bin/
    transmission-daemon
    transmission-cli
    transmission-remote
    transmission-create
    transmission-edit
    transmission-show
  lib/
    libcurl.so.4
    libssl.so.3
    libcrypto.so.3
    libstdc++.so.6
    libgcc_s.so.1
  share/
    ... Transmission web assets ...
```

Exact installed paths should follow Transmission's CMake install result rather than being guessed where practical.

The staged binaries must use a NAS-safe private-library strategy. Preferred direction is an install-time relative RPATH such as:

```text
$ORIGIN/../lib
```

A wrapper that sets `LD_LIBRARY_PATH` is a fallback, not the first choice.

The bundle phase must also:

- copy the GCC 10 runtime `libstdc++.so.6` and `libgcc_s.so.1` from the selected devtoolset;
- audit those copied runtime libraries for GLIBC requirements;
- re-audit every ELF in the staged bundle;
- smoke-test `transmission-daemon --version` from the staged tree without relying on `/opt/transmission-deps`;
- verify the final RPATH/RUNPATH and resolved dependency set;
- archive/upload the standalone tree as an Actions artifact.

Do not treat the build-tree ABI pass as the final package audit; the staged bundle is a separate release gate.

## Installed NAS Transmission processes observed during investigation

Live inspection showed two independent services:

```text
root  /usr/local/AppCentral/download-center/bin/transmissiond --no-utp --config-dir /usr/local/AppCentral/download-center/etc --no-watch-dir
admin /usr/local/AppCentral/transmission/bin/transmission-daemon --pid-file /var/run/transmission-daemon.pid -g /usr/local/AppCentral/transmission/config
```

The App Central Transmission daemon was observed listening on:

```text
0.0.0.0:9091
0.0.0.0:53297
```

Download Center must not be mistaken for the package being rebuilt during later stop/start testing.

## Upgrade-data preservation

The installed Transmission data is valuable and must not be recreated blindly. Before any App Central replacement, verify final CONTROL scripts and lifecycle behavior against Matt's original package so stop/start/upgrade actions do not delete or overwrite existing configuration, torrent or resume state.

## TLS workaround to retire

The user's installed package had a local 2022 modification:

```sh
TR_CURL_SSL_NO_VERIFY=1; export TR_CURL_SSL_NO_VERIFY
```

This is explicitly excluded from the rebuild. Proper CA validation is part of the modernization goal.

## Workflow/session discipline

- GitHub Actions is the canonical home of raw build logs/artifacts.
- `PROJECT-STATE.md` is the canonical compact checkpoint.
- `BUILD-NOTES.md` records durable technical rationale/findings.
- After a meaningful build result, source-compatibility discovery, packaging decision or NAS validation step, update these notes before considering the step closed.
- When a chat thread becomes large, begin the next session by reading these files and the latest relevant commits/workflow runs instead of reconstructing history from pasted logs.
