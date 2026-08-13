# transmission-asustor

Cross-build project for running **Transmission 4.1.1** on a legacy **ASUSTOR AS-608T** (x86-64).

## Target

- NAS: ASUSTOR AS-608T
- Architecture: x86-64
- Kernel: 3.12.20
- Runtime glibc: 2.22
- Transmission target: 4.1.1
- Existing App Central package: Transmission 3.00, maintained by Matt

## Build strategy

The existing ASUSTOR package is dynamically linked and ships private copies of curl, OpenSSL, libevent and zlib under the application `lib/` directory. This project follows the same model rather than depending on ADM's old system SSL stack.

The first GitHub Actions stage is deliberately non-destructive: it downloads and probes ASUSTOR's official legacy x86-64 cross-toolchain so we can establish the compiler, sysroot and target ABI before attempting the full dependency stack.

Later stages will build a **standalone test bundle first**. The bundle must be copied to a separate directory on the NAS and tested with `--version`, `file` and `ldd` before any App Central upgrade is attempted.

## Packaging

Matt's original package layout and CONTROL scripts are retained as a compatibility reference. Existing `config/` data — including settings, `.torrent` files, resume state, DHT, blocklists and statistics — must survive an upgrade.

The installed NAS package was locally modified in 2022 with:

```sh
TR_CURL_SSL_NO_VERIFY=1; export TR_CURL_SSL_NO_VERIFY
```

That line is **not present in Matt's original Transmission 3.00 package**. It was a local HTTPS workaround and will not be carried into the new package. The new build will use proper CA certificate verification.

## Current phase

1. Probe the official ASUSTOR x86-64 toolchain.
2. Determine its compiler/sysroot/glibc baseline.
3. Build a modern private dependency stack compatible with the NAS.
4. Cross-build Transmission 4.1.1.
5. Produce a standalone test bundle.
6. Only after successful NAS validation, build an ASUSTOR `.apk` upgrade package.
