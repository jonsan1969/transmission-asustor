#!/bin/sh
set -eu

PKG_DIR=${APKG_PKG_DIR:-/usr/local/AppCentral/transmission}
STATUS=${APKG_PKG_STATUS:-}
CONFIG_DIR="$PKG_DIR/config"

case "$STATUS" in
    install|upgrade)
        :
        ;;
    *)
        echo "Unsupported APKG_PKG_STATUS: $STATUS" >&2
        exit 1
        ;;
esac

mkdir -p "$CONFIG_DIR"

if [ -n "${APKG_TEMP_DIR:-}" ]; then
    BACKUP_DIR="$APKG_TEMP_DIR/transmission-config-backup"
    if [ -f "$BACKUP_DIR/.apkg-backup-complete" ]; then
        rm -f "$BACKUP_DIR/.apkg-backup-complete"
        cp -a "$BACKUP_DIR/." "$CONFIG_DIR/"
    elif [ "$STATUS" = upgrade ]; then
        echo "Transmission upgrade backup marker is missing; refusing unsafe restore" >&2
        exit 1
    fi
elif [ "$STATUS" = upgrade ]; then
    echo "APKG_TEMP_DIR is required for safe Transmission upgrade restore" >&2
    exit 1
fi

chown -R admin:administrators "$CONFIG_DIR"
chmod 0775 "$CONFIG_DIR"
exit 0
