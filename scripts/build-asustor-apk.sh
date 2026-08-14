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

rm -rf "$WORK"
mkdir -p "$APP_DIR" "$PKG_DIR"
cp -a "$PAYLOAD/." "$APP_DIR/"
cp -a "$CONTROL_SRC" "$APP_DIR/CONTROL"

# Match ASUSTOR apkg-tools.py behavior: CONTROL shell hooks are executable
# in control.tar.gz regardless of their repository file mode.
find "$APP_DIR/CONTROL" -type f -name '*.sh' -exec chmod 0755 {} \;
find "$APP_DIR/CONTROL" -type f ! -name '*.sh' -exec chmod 0644 {} \;
chmod 0755 "$APP_DIR/CONTROL"

# User state must never be shipped in the package. An empty config directory is
# intentional: pre-install backs up existing state, package replacement creates
# the target layout, and post-install restores the saved state on upgrade.
rm -rf "$APP_DIR/config"
mkdir -p "$APP_DIR/config"

log "=== UPGRADE SAFETY GATE ==="
for required in pre-install.sh post-install.sh start-stop.sh config.json; do
    test -f "$APP_DIR/CONTROL/$required" || fail "missing CONTROL/$required"
    log "PASS control: $required"
done

if find "$APP_DIR/config" -mindepth 1 -print -quit | grep -q .; then
    fail "package config directory contains files; refusing to risk user state"
fi
log "PASS: packaged config directory is empty"

# Guard the migration semantics we deliberately inherited from Matt's package.
grep -Fq 'transmission-config-backup' "$APP_DIR/CONTROL/pre-install.sh" || fail "pre-install backup logic missing"
grep -Fq '.apkg-backup-complete' "$APP_DIR/CONTROL/pre-install.sh" || fail "pre-install backup marker missing"
grep -Fq '.apkg-backup-complete' "$APP_DIR/CONTROL/post-install.sh" || fail "post-install restore marker check missing"
for excluded in CONTROL bin lib share web www; do
    grep -Fq "\$BACKUP_DIR/$excluded" "$APP_DIR/CONTROL/pre-install.sh" || fail "legacy migration exclusion missing: $excluded"
done
log "PASS: Matt-compatible upgrade backup/restore guards are present"

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
test -x "$WORK/inspect-control/pre-install.sh" || fail "pre-install.sh lost executable bit"
test -x "$WORK/inspect-control/post-install.sh" || fail "post-install.sh lost executable bit"
test -x "$WORK/inspect-control/start-stop.sh" || fail "start-stop.sh lost executable bit"
test ! -e "$WORK/inspect-data/CONTROL" || fail "CONTROL leaked into data.tar.gz"
if find "$WORK/inspect-data/config" -mindepth 1 -print -quit | grep -q .; then
    fail "state leaked into packaged config directory"
fi
log "PASS: control/data archives round-trip with safe separation"

APK_BYTES=$(stat -c '%s' "$APK")
APK_HUMAN=$(du -h "$APK" | awk '{print $1}')
log "APK: $APK"
log "APK size: $APK_BYTES bytes ($APK_HUMAN)"
log "ASUSTOR APK BUILD: PASS"
