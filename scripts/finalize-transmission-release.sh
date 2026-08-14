#!/usr/bin/env bash
set -euxo pipefail

source /opt/rh/devtoolset-10/enable

STAGE=/work/out/transmission-standalone
ARCHIVE=/work/transmission-standalone.tar.gz
REPORT=/work/standalone-release-check.txt
TARGET_GLIBC=2.22

DAEMON="$STAGE/bin/transmission-daemon"
WRAPPER="$STAGE/bin/transmission-daemon-bundled"
CURL_BIN="$STAGE/bin/curl"
CA_BUNDLE="$STAGE/share/certs/ca-bundle.crt"
WEB_HOME="$STAGE/share/transmission/public_html"

: > "$REPORT"

log() {
  printf '%s\n' "$*" | tee -a "$REPORT"
}

log "=== RELEASE FINALIZATION ==="
log "stage: $STAGE"
log "target GLIBC ceiling: GLIBC_$TARGET_GLIBC"

test -d "$STAGE"
test -x "$DAEMON"
test -x "$CURL_BIN"
test -s "$CA_BUNDLE"
test -f "$WEB_HOME/index.html"

log "=== INSTALL RELOCATABLE STANDALONE WRAPPER ==="
cat > "$WRAPPER" <<'WRAPPER_EOF'
#!/bin/sh
set -eu
BIN_DIR=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$BIN_DIR/.." && pwd -P)
export TRANSMISSION_WEB_HOME="$ROOT/share/transmission/public_html"
export CURL_CA_BUNDLE="$ROOT/share/certs/ca-bundle.crt"
export SSL_CERT_FILE="$ROOT/share/certs/ca-bundle.crt"
if [ -d "$ROOT/lib/ossl-modules" ]; then
  export OPENSSL_MODULES="$ROOT/lib/ossl-modules"
fi
exec "$ROOT/bin/transmission-daemon" "$@"
WRAPPER_EOF
chmod 0755 "$WRAPPER"

grep -Fq 'TRANSMISSION_WEB_HOME="$ROOT/share/transmission/public_html"' "$WRAPPER"
log "PASS: wrapper sets relocatable TRANSMISSION_WEB_HOME"

BEFORE_BYTES=$(du -sb "$STAGE" | awk '{print $1}')
BEFORE_HUMAN=$(du -sh "$STAGE" | awk '{print $1}')
log "pre-strip staged size: $BEFORE_BYTES bytes ($BEFORE_HUMAN)"

log "=== SNAPSHOT DELIVERABLE ELF FILES ==="
ELF_FILES=()
while IFS= read -r -d '' candidate; do
  if readelf -h "$candidate" >/dev/null 2>&1; then
    ELF_FILES+=("$candidate")
  fi
done < <(find "$STAGE" -type f -print0 | sort -z)

ELF_COUNT=${#ELF_FILES[@]}
if [ "$ELF_COUNT" -eq 0 ]; then
  log "ERROR: no ELF files found to strip"
  exit 1
fi
log "ELF files selected for strip: $ELF_COUNT"

log "=== STRIP DELIVERABLE ELF FILES ==="
for candidate in "${ELF_FILES[@]}"; do
  log "strip: ${candidate#$STAGE/}"
  strip --strip-unneeded "$candidate"
done
log "stripped ELF files: $ELF_COUNT"

AFTER_BYTES=$(du -sb "$STAGE" | awk '{print $1}')
AFTER_HUMAN=$(du -sh "$STAGE" | awk '{print $1}')
SAVED_BYTES=$((BEFORE_BYTES - AFTER_BYTES))
log "post-strip staged size: $AFTER_BYTES bytes ($AFTER_HUMAN)"
log "saved by strip: $SAVED_BYTES bytes"

if [ "$AFTER_BYTES" -ge "$BEFORE_BYTES" ]; then
  log "ERROR: stripping did not reduce staged size"
  exit 1
fi

log "=== POST-STRIP ELF / ABI / RPATH GATE ==="
ABI_FAIL=0
for elf in "${ELF_FILES[@]}"; do
  if ! readelf -h "$elf" >/dev/null 2>&1; then
    log "ELF ERROR: ${elf#$STAGE/} is missing or invalid after strip"
    ABI_FAIL=1
    continue
  fi

  rel="${elf#$STAGE/}"
  max_glibc=$(strings "$elf" | grep -oE 'GLIBC_[0-9.]+' | sed 's/^GLIBC_//' | sort -V | tail -1 || true)
  max_glibcxx=$(strings "$elf" | grep -oE 'GLIBCXX_[0-9.]+' | sed 's/^GLIBCXX_//' | sort -V | tail -1 || true)
  max_cxxabi=$(strings "$elf" | grep -oE 'CXXABI_[0-9.]+' | sed 's/^CXXABI_//' | sort -V | tail -1 || true)

  log "ELF: $rel"
  log "  max GLIBC: ${max_glibc:+GLIBC_}$max_glibc"
  log "  max GLIBCXX: ${max_glibcxx:+GLIBCXX_}$max_glibcxx"
  log "  max CXXABI: ${max_cxxabi:+CXXABI_}$max_cxxabi"

  if [ -n "$max_glibc" ] && [ "$(printf '%s\n%s\n' "$TARGET_GLIBC" "$max_glibc" | sort -V | tail -1)" != "$TARGET_GLIBC" ]; then
    log "ABI ERROR: $rel requires GLIBC_$max_glibc"
    ABI_FAIL=1
  fi

  if readelf -d "$elf" 2>/dev/null | grep -Fq '/opt/transmission-deps'; then
    log "RPATH ERROR: $rel still contains /opt/transmission-deps"
    ABI_FAIL=1
  fi
done

[ "$ABI_FAIL" -eq 0 ] || exit 1
log "PASS: post-strip GLIBC/build-prefix gate"

log "=== POST-STRIP EXECUTABLE RPATH GATE ==="
for elf in "$STAGE"/bin/*; do
  if [ -f "$elf" ] && file "$elf" | grep -q 'ELF 64-bit'; then
    if ! readelf -d "$elf" | grep -Fq '$ORIGIN/../lib'; then
      log "ERROR: ${elf#$STAGE/} lacks expected \$ORIGIN/../lib RPATH"
      exit 1
    fi
    log "PASS RPATH: ${elf#$STAGE/}"
  fi
done

log "=== POST-STRIP RUNTIME GATE ==="
env -u LD_LIBRARY_PATH "$DAEMON" --version 2>&1 | tee -a "$REPORT"
env -u LD_LIBRARY_PATH "$WRAPPER" --version 2>&1 | tee -a "$REPORT"

LDD_OUT=$(env -u LD_LIBRARY_PATH ldd "$DAEMON" 2>&1)
printf '%s\n' "$LDD_OUT" | tee -a "$REPORT"

if grep -qF 'not found' <<<"$LDD_OUT"; then
  log "ERROR: unresolved dependency after strip"
  exit 1
fi
if grep -qF '/opt/transmission-deps' <<<"$LDD_OUT"; then
  log "ERROR: daemon resolves dependency from build prefix after strip"
  exit 1
fi

for private_lib in libcurl.so.4 libssl.so.3 libcrypto.so.3 libstdc++.so.6 libgcc_s.so.1; do
  resolved_line=$(grep -F "$private_lib" <<<"$LDD_OUT" | head -1 || true)
  if [[ -z "$resolved_line" || "$resolved_line" != *"$STAGE/"* ]]; then
    log "ERROR: $private_lib is not resolved from standalone tree after strip"
    exit 1
  fi
  log "PASS: $resolved_line"
done

log "=== POST-STRIP TLS GATE ==="
env -u LD_LIBRARY_PATH \
  CURL_CA_BUNDLE="$CA_BUNDLE" \
  SSL_CERT_FILE="$CA_BUNDLE" \
  "$CURL_BIN" --fail --silent --show-error --retry 2 --connect-timeout 10 --max-time 30 \
  -o /dev/null https://curl.se/
log "PASS: verified HTTPS through staged curl/OpenSSL/CA after strip"

log "=== REBUILD FINAL ARCHIVE ==="
rm -f "$ARCHIVE"
tar -C /work/out -czf "$ARCHIVE" transmission-standalone
ARCHIVE_BYTES=$(stat -c '%s' "$ARCHIVE")
ARCHIVE_HUMAN=$(du -h "$ARCHIVE" | awk '{print $1}')
log "final archive size: $ARCHIVE_BYTES bytes ($ARCHIVE_HUMAN)"
log "RELEASE FINALIZATION: PASS"
