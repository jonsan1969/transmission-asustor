#!/bin/sh
set -eu

ROOT=${ROOT:-/work}
PAYLOAD=${PAYLOAD:-$ROOT/out/transmission-apkg-payload}
CONTROL_SRC=${CONTROL_SRC:-$ROOT/package/CONTROL}
WORK=${WORK:-$ROOT/out/asustor-apk}
APP_DIR="$WORK/transmission"
PKG_DIR="$WORK/package"
APK="$ROOT/transmission_4.1.1_x86-64.apk"
REPORT="$ROOT/asustor-apk-check.txt"

# The three 90x90 legacy ADM icons are preserved from Matt's official
# Transmission 3.00 ASUSTOR package. They are vendored in package/CONTROL so
# historical App Central availability is not a build-time dependency.
ICON_SHA_ENABLED=9b08828efa4b7cae7e8329038b363aec397738060f973081898b5ce65b4e7690
ICON_SHA_DISABLED=fcc419d0b67c8cea0808c9a696af037067e796e298122ca0b8a3cb52608030b3

: > "$REPORT"

log() {
    printf '%s\n' "$*" | tee -a "$REPORT"
}

fail() {
    log "ERROR: $*"
    exit 1
}

log "=== ASUSTOR APK BUILD ==="
log "payload: $PAYLOAD"
log "control: $CONTROL_SRC"

test -d "$PAYLOAD" || fail "APKG payload tree is missing"
test -d "$CONTROL_SRC" || fail "CONTROL source tree is missing"
test -x "$PAYLOAD/bin/transmission-daemon" || fail "Transmission daemon is missing from payload"
test -f "$CONTROL_SRC/config.json" || fail "CONTROL/config.json is missing"
test -f "$CONTROL_SRC/license.txt" || fail "CONTROL/license.txt is missing"

rm -rf "$WORK"
mkdir -p "$APP_DIR" "$PKG_DIR"
cp -a "$PAYLOAD/." "$APP_DIR/"
cp -a "$CONTROL_SRC" "$APP_DIR/CONTROL"

log "=== LEGACY ADM CONTROL ASSETS ==="
command -v python3 >/dev/null 2>&1 || fail "python3 is required to validate PNG icon assets"

for icon in icon.png icon-enable.png icon-disable.png; do
    test -s "$APP_DIR/CONTROL/$icon" || fail "vendored legacy icon missing: $icon"
done

[ "$(sha256sum "$APP_DIR/CONTROL/icon.png" | awk '{print $1}')" = "$ICON_SHA_ENABLED" ] || fail "icon.png SHA-256 mismatch"
[ "$(sha256sum "$APP_DIR/CONTROL/icon-enable.png" | awk '{print $1}')" = "$ICON_SHA_ENABLED" ] || fail "icon-enable.png SHA-256 mismatch"
[ "$(sha256sum "$APP_DIR/CONTROL/icon-disable.png" | awk '{print $1}')" = "$ICON_SHA_DISABLED" ] || fail "icon-disable.png SHA-256 mismatch"

python3 - "$APP_DIR/CONTROL" <<'PY' || exit 1
import pathlib
import struct
import sys

control = pathlib.Path(sys.argv[1])
for name in ("icon.png", "icon-enable.png", "icon-disable.png"):
    path = control / name
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"ERROR: {name} is not a PNG")
    if len(data) < 24 or data[12:16] != b"IHDR":
        raise SystemExit(f"ERROR: {name} has invalid PNG IHDR")
    width, height = struct.unpack(">II", data[16:24])
    if (width, height) != (90, 90):
        raise SystemExit(f"ERROR: {name} is {width}x{height}, expected 90x90")
    print(f"PASS icon: {name} ({width}x{height}, {len(data)} bytes)")
PY
log "PASS: vendored Matt 3.00 legacy ADM icons verified by SHA-256 and dimensions"

# Match ASUSTOR apkg-tools.py behavior: CONTROL shell hooks are executable
# in control.tar.gz regardless of their repository file mode.
find "$APP_DIR/CONTROL" -type f -name '*.sh' -exec chmod 0755 {} \;
find "$APP_DIR/CONTROL" -type f ! -name '*.sh' -exec chmod 0644 {} \;
chmod 0755 "$APP_DIR/CONTROL"

# User state must never be shipped in the package. An empty config directory is
# intentional: pre-install backs up existing state, package replacement creates
# the target layout, and post-install restores the saved state when one exists.
rm -rf "$APP_DIR/config"
mkdir -p "$APP_DIR/config"

log "=== UPGRADE SAFETY GATE ==="
for required in pre-install.sh post-install.sh start-stop.sh config.json description.txt changelog.txt license.txt icon.png icon-enable.png icon-disable.png; do
    test -f "$APP_DIR/CONTROL/$required" || fail "missing CONTROL/$required"
    log "PASS control: $required"
done

if find "$APP_DIR/config" -mindepth 1 -print -quit | grep -q .; then
    fail "package config directory contains files; refusing to risk user state"
fi
log "PASS: packaged config directory is empty"

# Guard the migration semantics inherited from Matt while also covering old
# ADM Manual Install, which can replace an existing package while reporting
# APKG_PKG_STATUS=install rather than upgrade.
grep -Fq 'transmission-config-backup' "$APP_DIR/CONTROL/pre-install.sh" || fail "pre-install backup logic missing"
grep -Fq '.apkg-backup-complete' "$APP_DIR/CONTROL/pre-install.sh" || fail "pre-install backup marker missing"
grep -Fq '.apkg-backup-complete' "$APP_DIR/CONTROL/post-install.sh" || fail "post-install restore marker check missing"
grep -Fq 'has_existing_state' "$APP_DIR/CONTROL/pre-install.sh" || fail "install-time existing-state detection missing"
grep -Fq 'install|upgrade' "$APP_DIR/CONTROL/post-install.sh" || fail "post-install install/upgrade restore handling missing"
grep -Fq 'chown -R admin:administrators "$CONFIG_DIR"' "$APP_DIR/CONTROL/post-install.sh" || fail "post-install NAS ownership target missing"
for excluded in CONTROL bin lib share web www; do
    grep -Fq "\$BACKUP_DIR/$excluded" "$APP_DIR/CONTROL/pre-install.sh" || fail "legacy migration exclusion missing: $excluded"
done
log "PASS: Matt-compatible backup/restore plus Manual Install state detection are present"
log "PASS: production post-install retains admin:administrators ownership"

log "=== LIFECYCLE REGRESSION TEST ==="
LIFECYCLE="$WORK/lifecycle-test"
OLD_PKG="$LIFECYCLE/old-package"
TEMP_DIR="$LIFECYCLE/temp"
TEST_BIN="$LIFECYCLE/test-bin"
rm -rf "$LIFECYCLE"
mkdir -p "$OLD_PKG/config/torrents" "$OLD_PKG/config/resume" "$TEMP_DIR" "$TEST_BIN"

# The real NAS hook must chown restored state to admin:administrators, but that
# ASUSTOR account/group does not exist on a stock GitHub Ubuntu runner. Stub
# only chown during the filesystem-semantics regression; the safety gate above
# separately asserts that the production hook still carries the exact owner.
cat > "$TEST_BIN/chown" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$TEST_BIN/chown"

printf '%s\n' '{"rpc-port":9091}' > "$OLD_PKG/config/settings.json"
printf '%s\n' 'torrent-state' > "$OLD_PKG/config/torrents/example.torrent"
printf '%s\n' 'resume-state' > "$OLD_PKG/config/resume/example.resume"

APKG_PKG_DIR="$OLD_PKG" APKG_PKG_STATUS=install APKG_TEMP_DIR="$TEMP_DIR" \
    "$APP_DIR/CONTROL/pre-install.sh" || fail "Manual Install replacement pre-install regression failed"
test -f "$TEMP_DIR/transmission-config-backup/.apkg-backup-complete" || fail "Manual Install replacement did not create backup marker"
test -f "$TEMP_DIR/transmission-config-backup/torrents/example.torrent" || fail "Manual Install replacement did not back up torrent state"
test -f "$TEMP_DIR/transmission-config-backup/resume/example.resume" || fail "Manual Install replacement did not back up resume state"

rm -rf "$OLD_PKG"
mkdir -p "$OLD_PKG/config"
PATH="$TEST_BIN:$PATH" APKG_PKG_DIR="$OLD_PKG" APKG_PKG_STATUS=install APKG_TEMP_DIR="$TEMP_DIR" \
    "$APP_DIR/CONTROL/post-install.sh" || fail "Manual Install replacement post-install regression failed"
test -f "$OLD_PKG/config/settings.json" || fail "Manual Install replacement did not restore settings"
test -f "$OLD_PKG/config/torrents/example.torrent" || fail "Manual Install replacement did not restore torrent state"
test -f "$OLD_PKG/config/resume/example.resume" || fail "Manual Install replacement did not restore resume state"
test ! -f "$TEMP_DIR/transmission-config-backup/.apkg-backup-complete" || fail "restore marker was not consumed"

CLEAN_PKG="$LIFECYCLE/clean-package"
mkdir -p "$CLEAN_PKG"
APKG_PKG_DIR="$CLEAN_PKG" APKG_PKG_STATUS=install \
    "$APP_DIR/CONTROL/pre-install.sh" || fail "clean install pre-install regression failed"
PATH="$TEST_BIN:$PATH" APKG_PKG_DIR="$CLEAN_PKG" APKG_PKG_STATUS=install APKG_TEMP_DIR="$LIFECYCLE/clean-temp" \
    "$APP_DIR/CONTROL/post-install.sh" || fail "clean install post-install regression failed"
test -d "$CLEAN_PKG/config" || fail "clean install did not create config directory"
log "PASS: lifecycle regression covers old-ADM install-labelled replacement and clean install"

# Confirm the package keeps our deliberate improvements over the historical
# package: true POSIX sh hooks and relocatable private runtime.
if grep -R -n '\[\[' "$APP_DIR/CONTROL" --include='*.sh' >> "$REPORT" 2>&1; then
    fail "Bash [[ ]] found under #!/bin/sh"
fi
for elf in "$APP_DIR"/bin/transmission-*; do
    test -f "$elf" || continue
    readelf -d "$elf" | grep -Fq '$ORIGIN/../lib' || fail "missing relocatable RPATH: ${elf#$APP_DIR/}"
done
log "PASS: CONTROL hooks remain POSIX and binaries retain \$ORIGIN/../lib"

log "=== BUILD APKG 2.0 CONTAINERS ==="
printf '2.0\n' > "$PKG_DIR/apkg-version"

tar -C "$APP_DIR/CONTROL" -czf "$PKG_DIR/control.tar.gz" .
tar -C "$APP_DIR" --exclude='./CONTROL' -czf "$PKG_DIR/data.tar.gz" .

rm -f "$APK"
(
    cd "$PKG_DIR"
    zip -q -X "$APK" apkg-version control.tar.gz data.tar.gz
)

log "=== FINAL APK STRUCTURE GATE ==="
MEMBERS=$(unzip -Z1 "$APK")
EXPECTED=$(printf '%s\n' apkg-version control.tar.gz data.tar.gz)
[ "$MEMBERS" = "$EXPECTED" ] || {
    log "actual members:"
    printf '%s\n' "$MEMBERS" | tee -a "$REPORT"
    fail "APK top-level members differ from ASUSTOR APKG 2.0 format"
}
log "PASS: APK contains exactly apkg-version, control.tar.gz, data.tar.gz"

[ "$(unzip -p "$APK" apkg-version)" = '2.0' ] || fail "invalid apkg-version"
log "PASS: apkg-version = 2.0"

rm -rf "$WORK/inspect-control" "$WORK/inspect-data"
mkdir -p "$WORK/inspect-control" "$WORK/inspect-data"
tar -xzf "$PKG_DIR/control.tar.gz" -C "$WORK/inspect-control"
tar -xzf "$PKG_DIR/data.tar.gz" -C "$WORK/inspect-data"

test -f "$WORK/inspect-control/config.json" || fail "config.json missing after control archive round-trip"
test -f "$WORK/inspect-control/license.txt" || fail "license.txt missing after control archive round-trip"
for icon in icon.png icon-enable.png icon-disable.png; do
    test -s "$WORK/inspect-control/$icon" || fail "$icon missing after control archive round-trip"
done
test -x "$WORK/inspect-control/pre-install.sh" || fail "pre-install.sh lost executable bit"
test -x "$WORK/inspect-control/post-install.sh" || fail "post-install.sh lost executable bit"
test -x "$WORK/inspect-control/start-stop.sh" || fail "start-stop.sh lost executable bit"
test ! -e "$WORK/inspect-data/CONTROL" || fail "CONTROL leaked into data.tar.gz"
if find "$WORK/inspect-data/config" -mindepth 1 -print -quit | grep -q .; then
    fail "state leaked into packaged config directory"
fi
log "PASS: control/data archives round-trip with complete legacy ADM presentation assets and safe separation"

APK_BYTES=$(stat -c '%s' "$APK")
APK_HUMAN=$(du -h "$APK" | awk '{print $1}')
log "APK: $APK"
log "APK size: $APK_BYTES bytes ($APK_HUMAN)"
log "ASUSTOR APK BUILD: PASS"
