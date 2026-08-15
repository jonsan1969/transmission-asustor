#!/usr/bin/env bash
set -euxo pipefail

BASE=/work/scripts/build-transmission-standalone.sh
TMP=/tmp/build-transmission-source-rpc.sh
cp "$BASE" "$TMP"

# ASUSTOR compatibility patch: Matt's clean 3.00 package is reachable from LAN
# immediately and produces an effective rpc-whitelist-enabled=false setting.
# Transmission 4.1.1 upstream defaults this to true. Patch only the daemon's
# compiled clean-config default; existing settings.json files remain authoritative.
INSERT_AFTER='sed -i "/is_ipv6_6to4() const noexcept/s/constexpr //" /tmp/transmission-src/libtransmission/net.h'

grep -Fq "$INSERT_AFTER" "$TMP"

sed -i "/is_ipv6_6to4() const noexcept\/s\/constexpr \/\//a\\
\\
# ASUSTOR RPC clean-install default: allow LAN WebUI/Remote GUI like Matt 3.00.\\
grep -Fq 'app_defaults_map.try_emplace(TR_KEY_rpc_enabled, true);' /tmp/transmission-src/daemon/daemon.cc\\
sed -i '/app_defaults_map.try_emplace(TR_KEY_rpc_enabled, true);/a\\    app_defaults_map.try_emplace(TR_KEY_rpc_whitelist_enabled, false);' /tmp/transmission-src/daemon/daemon.cc\\
grep -n -A2 -B2 'TR_KEY_rpc_whitelist_enabled' /tmp/transmission-src/daemon/daemon.cc" "$TMP"

chmod +x "$TMP"
exec "$TMP"
