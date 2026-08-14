# Mission Transmission Rebuild — Build Notes

This file records technical findings and rationale that should survive chat/session boundaries. Keep `PROJECT-STATE.md` concise; put deeper build details here.

## Target and compatibility model

The goal is not merely to compile Transmission 4.1.1. The produced binaries must actually run on the ASUSTOR AS-608T runtime:

- x86-64
- kernel 3.12.20
- glibc 2.22

The resulting App Central package should remain self-contained enough to avoid relying on obsolete ADM networking/crypto libraries where practical.

## Why not simply use the original ASUSTOR toolchain?

ASUSTOR's official ADM 2.0 x86-64 cross-toolchain is retained and probed as an ABI/reference source, but modern Transmission requires a substantially newer C++ compiler and C++17 support.

Therefore the project moved to a hybrid strategy:

- preserve an old userspace/glibc baseline,
- use a modern-enough compiler,
- build required modern userland dependencies privately,
- audit all final ELF symbol requirements.

The selected experimental environment is manylinux2014 with devtoolset-10/GCC 10.

## manylinux2014 Build Probe

The Transmission Build Probe pins the manylinux2014 image by digest:

```text
quay.io/pypa/manylinux2014_x86_64@sha256:0a42cb7e5f4ba6bbfb8d0a86d1aab0c8876ba9c3be16bd99360ae42bf010ec77
```

Within the container:

```sh
source /opt/rh/devtoolset-10/enable
```

Common compilation flags:

```text
CFLAGS=-O2 -march=x86-64 -mtune=generic
CXXFLAGS=-O2 -march=x86-64 -mtune=generic
```

Private prefix:

```text
/opt/transmission-deps
```

Environment used to locate private libraries includes:

```text
PKG_CONFIG_PATH=/opt/transmission-deps/lib64/pkgconfig:/opt/transmission-deps/lib/pkgconfig
LD_LIBRARY_PATH=/opt/transmission-deps/lib64:/opt/transmission-deps/lib:...
```

## OpenSSL 3.5.7

OpenSSL is built from upstream release source with shared libraries and without tests/docs for the probe:

```text
./Configure linux-x86_64 shared no-tests no-docs
```

Important build-environment finding: the manylinux2014 image needed additional Perl modules/packages for the selected OpenSSL release. The workflow installs:

- `perl-IPC-Cmd`
- `perl-Time-Piece`

Both are explicitly smoke-tested before building OpenSSL.

A later probe failure showed that a freshly built OpenSSL executable could not locate its private runtime libraries. The workflow therefore sets `LD_LIBRARY_PATH` to include both `$PREFIX/lib64` and `$PREFIX/lib` before using the private tools.

Relevant historical commits include:

- `0ad89aa274c087fc8b485a1192ad7fe6b4bb7de9` — install OpenSSL Time::Piece Perl dependency
- `0ddf142f09c9def5c1589e1689d7123d3a064cfc` — fix private OpenSSL runtime library lookup

## curl 8.21.0

curl is built against the private OpenSSL prefix with a deliberately reduced feature/dependency set for the initial probe.

Disabled/omitted in the current probe include LDAP/LDAPS and optional libpsl, zlib, brotli, zstd, libidn2, nghttp2, nghttp3, ngtcp2 and libssh2 integrations.

The immediate goal is to establish a minimal, controllable HTTPS-capable libcurl suitable for Transmission before deciding which optional features belong in the final package.

## Transmission 4.1.1 configure profile

Current probe configuration is focused on daemon/CLI functionality and disables desktop frontends and tests.

Notable settings:

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

The private curl and OpenSSL locations are passed explicitly to CMake.

Commit `016c3df27df5732ce2ea67d19eecf2ae5ed5d1f5` extended the probe from configuration-only testing into actual Transmission compilation plus ELF ABI auditing.

## GCC 10 vs Transmission 4.1.1: `is_ipv6_6to4()`

The first actual `libtransmission` compilation exposed a source/toolchain compatibility problem in:

```text
libtransmission/net.h
```

Upstream 4.1.1 defines:

```cpp
[[nodiscard]] constexpr bool is_ipv6_6to4() const noexcept
{
    return is_ipv6() && reinterpret_cast<uint16_t const*>(&addr.addr6)[0] == htons(0x2002U);
}
```

With GCC 10 plus the old glibc headers, `htons()` expands through code that causes GCC to report:

```text
error: uninitialized variable '__v' in 'constexpr' function
```

This is a compile-time constexpr compatibility issue, not evidence of an OpenSSL/curl/CMake/linker failure.

Chosen workaround: remove `constexpr` from this one function in the checked-out Transmission source during the probe. Do not carry a broad warning suppression or unrelated source changes.

The workflow first verifies the expected signature with `grep -q`, then applies the one-line `sed` patch. If upstream source changes, the probe fails rather than silently modifying an unexpected line.

Commit:

`0a751f7da64ac618acfbd565eb5823e06eed8db9` — Fix Transmission 4.1.1 GCC 10 constexpr build failure

## ABI audit philosophy

Passing compilation is only the first gate. For every Transmission executable and every private shared dependency intended for the final bundle, inspect:

1. ELF architecture/type (`file`)
2. program interpreter (`readelf -l`)
3. runtime dependencies (`readelf -d`, `NEEDED`)
4. `RPATH`/`RUNPATH`
5. highest required `GLIBC_*` symbol
6. highest required `GLIBCXX_*` symbol
7. highest required `CXXABI_*` symbol

The AS-608T has glibc 2.22, so a generated executable/library requiring a newer GLIBC symbol is not acceptable even if it builds and runs inside GitHub Actions.

Likewise, C++ runtime requirements must be satisfied deliberately in the standalone/private bundle; do not assume the NAS system `libstdc++` is new enough.

## Installed NAS Transmission processes observed during investigation

Live process inspection showed two independent Transmission-based services:

```text
root  /usr/local/AppCentral/download-center/bin/transmissiond --no-utp --config-dir /usr/local/AppCentral/download-center/etc --no-watch-dir
admin /usr/local/AppCentral/transmission/bin/transmission-daemon --pid-file /var/run/transmission-daemon.pid -g /usr/local/AppCentral/transmission/config
```

The App Central Transmission daemon was observed listening on:

```text
0.0.0.0:9091
0.0.0.0:53297
```

This matters for later smoke testing and process shutdown/startup. Download Center must not be mistaken for the package being rebuilt.

## Upgrade-data preservation

The installed Transmission data is valuable and must not be recreated blindly during package testing. The rebuild must preserve existing configuration/state including torrent/resume data.

Before any real App Central replacement, verify the final CONTROL scripts and package lifecycle behavior against Matt's original package so stop/start/upgrade semantics do not delete or overwrite the user's existing config.

## TLS workaround to retire

The user's installed package had a local 2022 modification:

```sh
TR_CURL_SSL_NO_VERIFY=1; export TR_CURL_SSL_NO_VERIFY
```

This is specifically excluded from the rebuild. Proper CA validation is part of the modernization goal.

## Workflow/session discipline

For future work:

- GitHub Actions is the canonical home of raw build logs.
- `PROJECT-STATE.md` is the canonical short checkpoint.
- `BUILD-NOTES.md` records durable technical rationale/findings.
- After a meaningful build result, source compatibility discovery, packaging decision or NAS validation step, update these notes before considering the step closed.
- When a chat thread becomes large, a new thread should begin by reading these files and the most recent relevant commits/workflow runs instead of reconstructing the project from pasted logs.
