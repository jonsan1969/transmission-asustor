#!/bin/sh
set -eu

PKG_DIR=${APKG_PKG_DIR:-/usr/local/AppCentral/transmission}
STATUS=${APKG_PKG_STATUS:-}

has_existing_state() {
    if [ -f "$PKG_DIR/config/settings.json" ] || \
       [ -f "$PKG_DIR/config/dht.dat" ] || \
       [ -f "$PKG_DIR/config/stats.json" ]; then
        return 0
    fi

    if [ -d "$PKG_DIR/config/torrents" ] && \
       find "$PKG_DIR/config/torrents" -type f -print -quit 2>/dev/null | grep -q .; then
        return 0
    fi

    if [ -d "$PKG_DIR/config/resume" ] && \
       find "$PKG_DIR/config/resume" -type f -print -quit 2>/dev/null | grep -q .; then
        return 0
    fi

    # Older package layouts may have stored state directly in the package root.
    if [ -f "$PKG_DIR/settings.json" ] || \
       [ -f "$PKG_DIR/dht.dat" ] || \
       [ -f "$PKG_DIR/stats.json" ]; then
        return 0
    fi

    if [ -d "$PKG_DIR/torrents" ] && \
       find "$PKG_DIR/torrents" -type f -print -quit 2>/dev/null | grep -q .; then
        return 0
    fi

    if [ -d "$PKG_DIR/resume" ] && \
       find "$PKG_DIR/resume" -type f -print -quit 2>/dev/null | grep -q .; then
        return 0
    fi

    return 1
}

case "$STATUS" in
    install)
        # Old ADM Manual Install can replace an already-installed package while
        # still reporting APKG_PKG_STATUS=install. Treat install as clean only
        # when no real Transmission state is present at the existing package path.
        if ! has_existing_state; then
            exit 0
        fi
        ;;
    upgrade)
        :
        ;;
    *)
        echo "Unsupported APKG_PKG_STATUS: $STATUS" >&2
        exit 1
        ;;
esac

if [ -z "${APKG_TEMP_DIR:-}" ]; then
    echo "APKG_TEMP_DIR is required for safe Transmission state preservation" >&2
    exit 1
fi

BACKUP_DIR="$APKG_TEMP_DIR/transmission-config-backup"
rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

if [ -d "$PKG_DIR/config" ]; then
    cp -a "$PKG_DIR/config/." "$BACKUP_DIR/"
else
    # Legacy package fallback: preserve state from the package root while
    # excluding program payload and package metadata.
    cp -a "$PKG_DIR/." "$BACKUP_DIR/"
    rm -rf \
        "$BACKUP_DIR/CONTROL" \
        "$BACKUP_DIR/bin" \
        "$BACKUP_DIR/lib" \
        "$BACKUP_DIR/share" \
        "$BACKUP_DIR/web" \
        "$BACKUP_DIR/www"
fi

touch "$BACKUP_DIR/.apkg-backup-complete"
exit 0
