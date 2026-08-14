#!/usr/bin/env bash
set -euxo pipefail

source /opt/rh/devtoolset-10/enable

GOLDEN=/work/out/transmission-standalone
PAYLOAD=/work/out/transmission-apkg-payload
ARCHIVE=/work/transmission-apkg-payload.tar.gz
REPORT=/work/apkg-payload-check.txt

: > "$REPORT"

log() {
  printf '%s\n' "$*" | tee -a "$REPORT"
}

log "=== APKG PAYLOAD PREPARATION ==="
log "golden tree: $GOLDEN"
log "payload tree: $PAYLOAD"

test -d "$GOLDEN"
test -x "$GOLDEN/bin/transmission-daemon"

rm -rf "$PAYLOAD"
cp -a "$GOLDEN" "$PAYLOAD"

GOLDEN_BYTES=$(du -sb "$GOLDEN" | awk '{print $1}')
GOLDEN_HUMAN=$(du -sh "$GOLDEN" | awk '{print $1}')
log "golden staged size: $GOLDEN_BYTES bytes ($GOLDEN_HUMAN)"

log "=== REMOVE BUILD/TEST-ONLY FILES ==="
remove_payload_file() {
  rel="$1"
  if [ -e "$PAYLOAD/$rel" ] || [ -L "$PAYLOAD/$rel" ]; then
    bytes=$(stat -c '%s' "$PAYLOAD/$rel" 2>/dev/null || printf '0')
    log "remove: $rel ($bytes bytes)"
    rm -f "$PAYLOAD/$rel"
  fi
}

# These belong to standalone/CI validation, not the installed App Central payload.
remove_payload_file bin/curl
remove_payload_file bin/transmission-daemon-bundled
remove_payload_file share/transmission/public_html/transmission-app.css.map

log "=== REQUIRED TRANSMISSION PROGRAM SET ==="
EXPECTED_BINS=(
  transmission-cli
  transmission-create
  transmission-daemon
  transmission-edit
  transmission-remote
  transmission-show
)

for name in "${EXPECTED_BINS[@]}"; do
  test -x "$PAYLOAD/bin/$name"
  log "PASS binary: bin/$name"
done

mapfile -t ACTUAL_BINS < <(find "$PAYLOAD/bin" -maxdepth 1 -type f -printf '%f\n' | sort)
mapfile -t EXPECTED_SORTED < <(printf '%s\n' "${EXPECTED_BINS[@]}" | sort)
if [ "$(printf '%s\n' "${ACTUAL_BINS[@]}")" != "$(printf '%s\n' "${EXPECTED_SORTED[@]}")" ]; then
  log "ERROR: unexpected APKG bin payload"
  log "actual: ${ACTUAL_BINS[*]}"
  log "expected: ${EXPECTED_SORTED[*]}"
  exit 1
fi
log "PASS: APKG bin payload matches Matt-compatible six-program set"

log "=== REQUIRED PRIVATE RUNTIME ==="
for rel in \
  lib/libcurl.so.4 \
  lib/libcurl.so.4.8.0 \
  lib/libssl.so.3 \
  lib/libcrypto.so.3 \
  lib/libstdc++.so.6 \
  lib/libgcc_s.so.1 \
  share/certs/ca-bundle.crt \
  share/transmission/public_html/index.html; do
  if [ ! -e "$PAYLOAD/$rel" ] && [ ! -L "$PAYLOAD/$rel" ]; then
    log "ERROR: required payload file missing: $rel"
    exit 1
  fi
  log "PASS required: $rel"
done

log "=== RETAINED FILE INTEGRITY GATE ==="
INTEGRITY_FAIL=0
while IFS= read -r -d '' src; do
  rel="${src#$GOLDEN/}"
  case "$rel" in
    bin/curl|bin/transmission-daemon-bundled|share/transmission/public_html/transmission-app.css.map)
      continue
      ;;
  esac

  dst="$PAYLOAD/$rel"
  if [ -L "$src" ]; then
    if [ ! -L "$dst" ] || [ "$(readlink "$src")" != "$(readlink "$dst")" ]; then
      log "INTEGRITY ERROR symlink: $rel"
      INTEGRITY_FAIL=1
    fi
  elif [ -f "$src" ]; then
    if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
      log "INTEGRITY ERROR file: $rel"
      INTEGRITY_FAIL=1
    fi
  fi
done < <(find "$GOLDEN" \( -type f -o -type l \) -print0)

[ "$INTEGRITY_FAIL" -eq 0 ] || exit 1
log "PASS: every retained payload file is byte-identical to golden release tree"

log "=== APKG RPATH / DEPENDENCY GATE ==="
for name in "${EXPECTED_BINS[@]}"; do
  elf="$PAYLOAD/bin/$name"
  if ! readelf -d "$elf" | grep -Fq '$ORIGIN/../lib'; then
    log "RPATH ERROR: bin/$name lacks expected \$ORIGIN/../lib"
    exit 1
  fi
  if readelf -d "$elf" | grep -Fq '/opt/transmission-deps'; then
    log "RPATH ERROR: bin/$name contains build prefix"
    exit 1
  fi
  log "PASS RPATH: bin/$name"
done

DAEMON="$PAYLOAD/bin/transmission-daemon"
env -u LD_LIBRARY_PATH "$DAEMON" --version 2>&1 | tee -a "$REPORT"

LDD_OUT=$(env -u LD_LIBRARY_PATH ldd "$DAEMON" 2>&1)
printf '%s\n' "$LDD_OUT" | tee -a "$REPORT"

if grep -qF 'not found' <<<"$LDD_OUT"; then
  log "ERROR: unresolved daemon dependency in APKG payload"
  exit 1
fi
if grep -qF '/opt/transmission-deps' <<<"$LDD_OUT"; then
  log "ERROR: daemon resolves dependency from build prefix in APKG payload"
  exit 1
fi

for private_lib in libcurl.so.4 libssl.so.3 libcrypto.so.3 libstdc++.so.6 libgcc_s.so.1; do
  resolved_line=$(grep -F "$private_lib" <<<"$LDD_OUT" | head -1 || true)
  if [[ -z "$resolved_line" || "$resolved_line" != *"$PAYLOAD/"* ]]; then
    log "ERROR: $private_lib is not resolved from APKG payload"
    exit 1
  fi
  log "PASS: $resolved_line"
done

log "=== TLS PAYLOAD CONTINUITY GATE ==="
# Full verified HTTPS is already executed against the golden tree immediately
# before this step. The APKG pruning step must not alter any TLS runtime input.
for rel in lib/libcurl.so.4.8.0 lib/libssl.so.3 lib/libcrypto.so.3 share/certs/ca-bundle.crt; do
  cmp -s "$GOLDEN/$rel" "$PAYLOAD/$rel"
  log "PASS TLS retained unchanged: $rel"
done

if ! readelf -d "$PAYLOAD/lib/libcurl.so.4.8.0" | grep -Fq 'Shared library: [libssl.so.3]'; then
  log "ERROR: packaged libcurl no longer declares libssl.so.3"
  exit 1
fi
if ! readelf -d "$PAYLOAD/lib/libcurl.so.4.8.0" | grep -Fq 'Shared library: [libcrypto.so.3]'; then
  log "ERROR: packaged libcurl no longer declares libcrypto.so.3"
  exit 1
fi
log "PASS: bundled libcurl retains OpenSSL linkage"

PAYLOAD_BYTES=$(du -sb "$PAYLOAD" | awk '{print $1}')
PAYLOAD_HUMAN=$(du -sh "$PAYLOAD" | awk '{print $1}')
SAVED_BYTES=$((GOLDEN_BYTES - PAYLOAD_BYTES))
log "APKG payload size: $PAYLOAD_BYTES bytes ($PAYLOAD_HUMAN)"
log "removed from golden standalone tree: $SAVED_BYTES bytes"

if [ "$PAYLOAD_BYTES" -ge "$GOLDEN_BYTES" ]; then
  log "ERROR: APKG payload pruning did not reduce size"
  exit 1
fi

log "=== BUILD APKG PAYLOAD ARCHIVE ==="
rm -f "$ARCHIVE"
tar -C /work/out -czf "$ARCHIVE" transmission-apkg-payload
ARCHIVE_BYTES=$(stat -c '%s' "$ARCHIVE")
ARCHIVE_HUMAN=$(du -h "$ARCHIVE" | awk '{print $1}')
log "APKG payload archive size: $ARCHIVE_BYTES bytes ($ARCHIVE_HUMAN)"
log "APKG PAYLOAD PREPARATION: PASS"
