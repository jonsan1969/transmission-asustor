#!/bin/sh
set -eu

PKG_DIR=${APKG_PKG_DIR:-/usr/local/AppCentral/transmission}
STATUS=${APKG_PKG_STATUS:-}

case "$STATUS" in
    install)
        exit 0
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
    echo "APKG_TEMP_DIR is required for safe Transmission upgrade" >&2
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
