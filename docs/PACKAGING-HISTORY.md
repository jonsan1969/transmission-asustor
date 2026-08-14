# Historical ASUSTOR Transmission packaging findings

This note records findings from archived native ASUSTOR Transmission packages examined before building the Transmission 4.1.1 App Central package.

## Packages examined

- Transmission 2.92-1 x86-64 — Fathi Boudra / fboudra line
- Transmission 2.92 x86-64 — Kosyak / Blueeyez-style line
- Transmission Dansk 2.92 x86-64 — closely related to the 2.92 package
- Transmission 2.94 x86-64 — Matt package line
- Transmission 3.00 x86-64 — Matt package line

## Packaging evolution

Three distinct packaging styles were observed:

1. Older 2.92 packages use a simpler layout and, in some cases, keep Transmission state outside the App Central package tree under `/share/Download/.transmission`.
2. Fathi's 2.92-1 package uses a more Unix-like `bin/`, `etc/`, `www/` structure.
3. Matt's 2.94/3.00 packages use the layout most suitable as the compatibility reference for the new package: `bin/`, `lib/`, `config/`, and Transmission web assets under the application tree.

Matt's 3.00 installation model is conceptually:

```text
/usr/local/AppCentral/transmission/
  bin/
  config/
  lib/
  share/transmission/web/
```

The Transmission 4.1.1 package should preserve the same high-level App Central conventions while retaining the new build's relocatable `$ORIGIN/../lib` runtime lookup instead of hard-coding `/usr/local/AppCentral/transmission/lib` into ELF RPATHs.

## Upgrade and migration behavior — required compatibility feature

Matt's 2.94/3.00 CONTROL scripts explicitly preserve user state during package upgrades.

The design to carry forward is:

- if a modern `${PKG_DIR}/config` directory exists, back up its contents to `${APKG_TEMP_DIR}` before replacement;
- support migration from older package layouts where Transmission state may not yet live under `config/`;
- when migrating such an older package tree, preserve user/state files but exclude program payload directories/files such as `CONTROL`, `bin`, `lib`, and web assets;
- after the new package is installed, recreate the new `config/` directory as needed and restore the preserved state;
- never discard settings, torrent metadata, resume data, DHT state, blocklists or statistics merely because the package layout changed.

The new implementation should keep Matt's migration semantics but use clear POSIX shell and explicit error handling.

## Start/stop behavior

Matt's 3.00 package starts Transmission as:

```text
admin:administrators
```

with configuration under:

```text
/usr/local/AppCentral/transmission/config
```

and PID file:

```text
/var/run/transmission-daemon.pid
```

The start-stop script uses `start-stop-daemon`, supports normal start/stop/restart/reload/status operations, waits for graceful shutdown and has a forced-stop fallback.

This matches the live AS-608T process observed during the project:

```text
/usr/local/AppCentral/transmission/bin/transmission-daemon --pid-file /var/run/transmission-daemon.pid -g /usr/local/AppCentral/transmission/config
```

The new package should retain the same service identity and configuration location unless live NAS validation exposes a reason not to.

## Web UI and App Central integration

Historical packages register RPC port 9091 with App Central and expose the Web UI through the package icon. Matt explicitly sets `TRANSMISSION_WEB_HOME` to the package's web asset directory.

The new package should use the equivalent path derived from the App Central package directory rather than an unnecessary absolute path where possible.

Historical package metadata also commonly uses:

```text
start-order: 20
stop-order: 80
```

These values are good compatibility defaults for the new package.

## Kernel UDP buffer tuning

Historical packages modify `net.core.rmem_max` and `net.core.wmem_max` at startup to avoid old Transmission UDP buffer warnings.

Do not copy these sysctl changes blindly. First test Transmission 4.1.1 on the physical NAS and add tuning only if the modern daemon demonstrates that it is still required.

## Package size comparison and stripping

Approximate archived APK sizes observed:

```text
2.92-1  ~1.7 MB
2.92    ~1.9 MB
2.94    ~3.7 MB
3.00    ~4.0 MB
```

Matt's released Transmission executables are stripped. The current 4.1.1 standalone artifact is substantially larger in part because its Transmission executables and private runtime ELF files are not yet stripped.

Release packaging should therefore follow this order:

1. build the full release binaries;
2. run ABI, RPATH, dependency and TLS validation on the unstripped staged tree;
3. strip the deliverable ELF executables/libraries;
4. re-run a post-strip runtime sanity check;
5. package the final App Central artifact.

The new package will still be larger than Matt's 3.00 package because it intentionally carries modern OpenSSL 3.x, modern curl, a private C++ runtime, CA trust and OpenSSL module support for old ADM systems. Matching the old 4 MB size is not a project goal.

## Packaging direction for Transmission 4.1.1

Planned structure:

```text
/usr/local/AppCentral/transmission/
  bin/
  config/                 # preserved across upgrades
  lib/
    ossl-modules/
  share/
    certs/
    transmission/
      public_html/
```

Key principles:

- run the daemon as `admin:administrators`;
- preserve `/var/run/transmission-daemon.pid` behavior;
- keep `config/` as durable user state;
- preserve Matt-compatible migration from older package generations;
- use relocatable `$ORIGIN/../lib` private-library lookup;
- use bundled CA trust and proper certificate verification;
- permanently omit the historical `TR_CURL_SSL_NO_VERIFY=1` workaround.
