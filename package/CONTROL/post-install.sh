#!/bin/sh
set -eu

PKG_DIR=${APKG_PKG_DIR:-/usr/local/AppCentral/transmission}
STATUS=${APKG_PKG_STATUS:-}
CONFIG_DIR="$PKG_DIR/config"

mkdir -p "$CONFIG_DIR"

case "$STATUS" in
    install)
        ;;
    upgrade)
        if [ -z "${APKG_TEMP_DIR:-}" ]; then
            echo "APKG_TEMP_DIR is required for safe Transmission upgrade" >&2
            exit 1
        fi
        BACKUP_DIR="$APKG_TEMP_DIR/transmission-config-backup"
        if [ ! -f "$BACKUP_DIR/.apkg-backup-complete" ]; then
            echo "Transmission upgrade backup marker is missing; refusing unsafe restore" >&2
            exit 1
        fi
        rm -f "$BACKUP_DIR/.apkg-backup-complete"
        cp -a "$BACKUP_DIR/." "$CONFIG_DIR/"
        ;;
    *)
        echo "Unsupported APKG_PKG_STATUS: $STATUS" >&2
        exit 1
        ;;
esac

chown -R admin:administrators "$CONFIG_DIR"
chmod 0775 "$CONFIG_DIR"
exit 0
