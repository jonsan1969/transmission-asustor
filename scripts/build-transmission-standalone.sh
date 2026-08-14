#!/usr/bin/env bash
set -euxo pipefail

source /opt/rh/devtoolset-10/enable

OPENSSL_VERSION=3.5.7
CURL_VERSION=8.21.0
PREFIX=/opt/transmission-deps
STAGE=/work/out/transmission-standalone
REPORT=/work/standalone-abi-audit.txt
RUNTIME_REPORT=/work/standalone-runtime-check.txt
TARGET_GLIBC=2.22

export MANPATH="${MANPATH:-}"
export CFLAGS="-O2 -march=x86-64 -mtune=generic"
export CXXFLAGS="-O2 -march=x86-64 -mtune=generic"
export PKG_CONFIG_PATH="$PREFIX/lib64/pkgconfig:$PREFIX/lib/pkgconfig"
export PATH="$PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$PREFIX/lib64:$PREFIX/lib:${LD_LIBRARY_PATH:-}"

echo "=== BUILD ENVIRONMENT ==="
gcc --version | head -1
g++ --version | head -1
cmake --version | head -1
/lib64/libc.so.6 | head -1 || true

echo "=== BUILD PREREQUISITES ==="
yum -y install perl-IPC-Cmd perl-Time-Piece
perl -MIPC::Cmd -e 'print qq(IPC::Cmd OK\n)'
perl -MTime::Piece -e 'print qq(Time::Piece OK\n)'

echo "=== BUILD OPENSSL $OPENSSL_VERSION ==="
rm -rf /tmp/openssl-src /tmp/openssl.tar.gz "$PREFIX"
mkdir -p "$PREFIX"
curl -L --fail --retry 3 -o /tmp/openssl.tar.gz \
  "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz"
mkdir /tmp/openssl-src
tar -xzf /tmp/openssl.tar.gz -C /tmp/openssl-src --strip-components=1
cd /tmp/openssl-src
./Configure linux-x86_64 shared no-tests no-docs --prefix="$PREFIX" --openssldir="$PREFIX/ssl"
make -j"$(nproc)"
make install_sw install_ssldirs
"$PREFIX/bin/openssl" version -a

echo "=== BUILD CURL $CURL_VERSION ==="
rm -rf /tmp/curl-src /tmp/curl.tar.xz
curl -L --fail --retry 3 -o /tmp/curl.tar.xz "https://curl.se/download/curl-$CURL_VERSION.tar.xz"
mkdir /tmp/curl-src
tar -xJf /tmp/curl.tar.xz -C /tmp/curl-src --strip-components=1
cd /tmp/curl-src
LDFLAGS="-L$PREFIX/lib64 -L$PREFIX/lib" CPPFLAGS="-I$PREFIX/include" ./configure \
  --prefix="$PREFIX" --with-openssl="$PREFIX" --enable-shared --disable-static \
  --disable-ldap --disable-ldaps --without-libpsl --without-zlib --without-brotli \
  --without-zstd --without-libidn2 --without-nghttp2 --without-nghttp3 \
  --without-ngtcp2 --without-libssh2
make -j"$(nproc)"
make install
"$PREFIX/bin/curl" --version

echo "=== FETCH + PATCH TRANSMISSION 4.1.1 ==="
rm -rf /tmp/transmission-src /tmp/transmission-build /work/out "$REPORT" "$RUNTIME_REPORT" /work/transmission-standalone.tar.gz
git clone --depth 1 --branch 4.1.1 --recurse-submodules https://github.com/transmission/transmission.git /tmp/transmission-src
grep -q "constexpr bool is_ipv6_6to4() const noexcept" /tmp/transmission-src/libtransmission/net.h
sed -i "/is_ipv6_6to4() const noexcept/s/constexpr //" /tmp/transmission-src/libtransmission/net.h

echo "=== CONFIGURE TRANSMISSION FOR RELOCATABLE STANDALONE INSTALL ==="
cmake -S /tmp/transmission-src -B /tmp/transmission-build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$STAGE" \
  -DCMAKE_INSTALL_RPATH='$ORIGIN/../lib' \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
  -DCMAKE_EXE_LINKER_FLAGS="-Wl,--disable-new-dtags" \
  -DCMAKE_PREFIX_PATH="$PREFIX" \
  -DCMAKE_C_STANDARD=11 -DCMAKE_CXX_STANDARD=17 \
  -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
  -DCURL_INCLUDE_DIR="$PREFIX/include" -DCURL_LIBRARY="$PREFIX/lib/libcurl.so" \
  -DOPENSSL_ROOT_DIR="$PREFIX" -DOPENSSL_USE_STATIC_LIBS=FALSE \
  -DENABLE_DAEMON=ON -DENABLE_CLI=ON -DENABLE_UTILS=ON \
  -DENABLE_GTK=OFF -DENABLE_QT=OFF -DENABLE_MAC=OFF -DENABLE_TESTS=OFF \
  -DENABLE_NLS=OFF -DINSTALL_DOC=OFF -DINSTALL_LIB=OFF -DREBUILD_WEB=OFF \
  -DINSTALL_WEB=ON -DWITH_SYSTEMD=OFF -DWITH_CRYPTO=openssl

cmake --build /tmp/transmission-build --parallel "$(nproc)"
cmake --install /tmp/transmission-build

echo "=== STAGE PRIVATE RUNTIME LIBRARIES ==="
mkdir -p "$STAGE/lib"
cp -L "$PREFIX/lib/libcurl.so.4.8.0" "$STAGE/lib/libcurl.so.4.8.0"
ln -sfn libcurl.so.4.8.0 "$STAGE/lib/libcurl.so.4"
cp -L "$PREFIX/lib64/libssl.so.3" "$STAGE/lib/libssl.so.3"
cp -L "$PREFIX/lib64/libcrypto.so.3" "$STAGE/lib/libcrypto.so.3"
cp -L "$(g++ -print-file-name=libstdc++.so.6)" "$STAGE/lib/libstdc++.so.6"
cp -L "$(gcc -print-file-name=libgcc_s.so.1)" "$STAGE/lib/libgcc_s.so.1"
find "$STAGE" -maxdepth 4 \( -type f -o -type l \) | sort

echo "=== VERIFY STAGED DAEMON USES RELATIVE PRIVATE LIBRARY PATH ==="
DAEMON="$STAGE/bin/transmission-daemon"
: > "$RUNTIME_REPORT"
{
  echo "=== STANDALONE RUNTIME PREFLIGHT ==="
  echo "stage: $STAGE"
  echo "daemon: $DAEMON"
  echo
} | tee -a "$RUNTIME_REPORT"

test -x "$DAEMON" || { echo "ERROR: staged transmission-daemon is missing/not executable" | tee -a "$RUNTIME_REPORT"; exit 1; }

{
  echo "=== DAEMON DYNAMIC SECTION ==="
  readelf -d "$DAEMON" | grep -E "RPATH|RUNPATH|NEEDED" || true
  echo
} | tee -a "$RUNTIME_REPORT"

if ! readelf -d "$DAEMON" | grep -Fq '$ORIGIN/../lib'; then
  echo "ERROR: staged daemon lacks expected \$ORIGIN/../lib RPATH/RUNPATH" | tee -a "$RUNTIME_REPORT"
  exit 1
fi

echo "=== DAEMON VERSION WITH LD_LIBRARY_PATH UNSET ===" | tee -a "$RUNTIME_REPORT"
if ! env -u LD_LIBRARY_PATH "$DAEMON" --version 2>&1 | tee -a "$RUNTIME_REPORT"; then
  echo "ERROR: staged daemon cannot execute using its own runtime search path" | tee -a "$RUNTIME_REPORT"
  exit 1
fi

LDD_OUT=$(env -u LD_LIBRARY_PATH ldd "$DAEMON" 2>&1) || {
  rc=$?
  printf '%s\n' "$LDD_OUT" | tee -a "$RUNTIME_REPORT"
  echo "ERROR: ldd failed with exit code $rc" | tee -a "$RUNTIME_REPORT"
  exit "$rc"
}
{
  echo
  echo "=== LDD WITH LD_LIBRARY_PATH UNSET ==="
  printf '%s\n' "$LDD_OUT"
  echo
} | tee -a "$RUNTIME_REPORT"

if grep -qF 'not found' <<<"$LDD_OUT"; then
  echo "ERROR: staged daemon has unresolved shared-library dependencies" | tee -a "$RUNTIME_REPORT"
  exit 1
fi
if grep -qF '/opt/transmission-deps' <<<"$LDD_OUT"; then
  echo "ERROR: staged daemon still resolves a library from the build-only prefix" | tee -a "$RUNTIME_REPORT"
  exit 1
fi

for private_lib in libcurl.so.4 libssl.so.3 libcrypto.so.3 libstdc++.so.6 libgcc_s.so.1; do
  resolved_line=$(grep -F "$private_lib" <<<"$LDD_OUT" | head -1 || true)
  if [[ -z "$resolved_line" ]]; then
    echo "ERROR: $private_lib is absent from daemon ldd output" | tee -a "$RUNTIME_REPORT"
    exit 1
  fi
  if [[ "$resolved_line" != *"$STAGE/"* ]]; then
    echo "ERROR: $private_lib did not resolve from the standalone tree: $resolved_line" | tee -a "$RUNTIME_REPORT"
    exit 1
  fi
  echo "PASS: $resolved_line" | tee -a "$RUNTIME_REPORT"
done

echo "RUNTIME PREFLIGHT: PASS" | tee -a "$RUNTIME_REPORT"

echo "=== FINAL STAGED ELF ABI AUDIT ==="
: > "$REPORT"
ABI_FAIL=0

audit_elf() {
  local elf="$1"
  local max_glibc max_glibcxx max_cxxabi
  if ! file "$elf" | grep -q "ELF 64-bit"; then return; fi
  max_glibc=$(strings "$elf" | grep -oE "GLIBC_[0-9.]+" | sed "s/^GLIBC_//" | sort -V | tail -1 || true)
  max_glibcxx=$(strings "$elf" | grep -oE "GLIBCXX_[0-9.]+" | sed "s/^GLIBCXX_//" | sort -V | tail -1 || true)
  max_cxxabi=$(strings "$elf" | grep -oE "CXXABI_[0-9.]+" | sed "s/^CXXABI_//" | sort -V | tail -1 || true)
  {
    echo "=== STAGED ELF ==="
    echo "file: ${elf#$STAGE/}"
    file "$elf"
    readelf -l "$elf" | grep "Requesting program interpreter" || true
    readelf -d "$elf" | grep -E "NEEDED|RPATH|RUNPATH" || true
    echo "max GLIBC:    ${max_glibc:+GLIBC_}$max_glibc"
    echo "max GLIBCXX:  ${max_glibcxx:+GLIBCXX_}$max_glibcxx"
    echo "max CXXABI:   ${max_cxxabi:+CXXABI_}$max_cxxabi"
    echo
  } | tee -a "$REPORT"
  if [ -n "$max_glibc" ] && [ "$(printf "%s\n%s\n" "$TARGET_GLIBC" "$max_glibc" | sort -V | tail -1)" != "$TARGET_GLIBC" ]; then
    echo "ABI ERROR: ${elf#$STAGE/} requires GLIBC_$max_glibc; target is <= GLIBC_$TARGET_GLIBC" | tee -a "$REPORT"
    ABI_FAIL=1
  fi
}

while IFS= read -r -d '' elf; do audit_elf "$elf"; done < <(find "$STAGE" -type f -print0 | sort -z)
{
  echo "=== STANDALONE BUNDLE SUMMARY ==="
  echo "AS-608T GLIBC ceiling: GLIBC_$TARGET_GLIBC"
  echo "Bundle root: transmission-standalone"
  if [ "$ABI_FAIL" -eq 0 ]; then echo "GLIBC gate: PASS"; else echo "GLIBC gate: FAIL"; fi
} | tee -a "$REPORT"
[ "$ABI_FAIL" -eq 0 ] || exit 1

echo "=== ARCHIVE STANDALONE BUNDLE ==="
tar -C /work/out -czf /work/transmission-standalone.tar.gz transmission-standalone
ls -lh /work/transmission-standalone.tar.gz "$REPORT" "$RUNTIME_REPORT"
echo "=== STANDALONE BUILD SUCCEEDED ==="
