#!/bin/sh
set -eu

PKG_DIR=${APKG_PKG_DIR:-/usr/local/AppCentral/transmission}
NAME=transmission-daemon
DAEMON="$PKG_DIR/bin/$NAME"
CONFIG_DIR="$PKG_DIR/config"
PIDFILE="/var/run/$NAME.pid"
USER=admin
GROUP=administrators

export TRANSMISSION_WEB_HOME="$PKG_DIR/share/transmission/public_html"
export CURL_CA_BUNDLE="$PKG_DIR/share/certs/ca-bundle.crt"
export SSL_CERT_FILE="$PKG_DIR/share/certs/ca-bundle.crt"
if [ -d "$PKG_DIR/lib/ossl-modules" ]; then
    export OPENSSL_MODULES="$PKG_DIR/lib/ossl-modules"
fi

start_daemon() {
    mkdir -p "$CONFIG_DIR"
    touch "$PIDFILE"
    chown "$USER:$GROUP" "$PIDFILE"
    chown "$USER:$GROUP" "$CONFIG_DIR"

    start-stop-daemon -S --quiet \
        --chuid "$USER:$GROUP" \
        --user "$USER" \
        --exec "$DAEMON" -- \
        --pid-file "$PIDFILE" \
        -g "$CONFIG_DIR"
}

_stop_daemon() {
    start-stop-daemon -K --quiet \
        --user "$USER" \
        --exec "$DAEMON" \
        --pidfile "$PIDFILE" "$@"
}

test_daemon() {
    _stop_daemon --test
}

wait_for_stop() {
    counter=0
    while [ "$counter" -lt 10 ]; do
        if ! test_daemon; then
            return 0
        fi
        counter=$((counter + 1))
        sleep 1
    done
    return 1
}

stop_daemon() {
    _stop_daemon || true
    if ! wait_for_stop; then
        echo "Taking too long, killing $NAME..."
        _stop_daemon --signal 9 || true
    fi
    rm -f "$PIDFILE"
}

reload_daemon() {
    _stop_daemon --signal 1
}

case "${1:-}" in
    start)
        if test_daemon; then
            echo "$NAME is already running"
        else
            echo "Starting $NAME..."
            start_daemon
        fi
        ;;
    stop)
        if test_daemon; then
            echo "Stopping $NAME..."
            stop_daemon
        else
            echo "$NAME is not running"
            rm -f "$PIDFILE"
        fi
        ;;
    restart)
        if test_daemon; then
            echo "Stopping $NAME..."
            stop_daemon
        fi
        echo "Starting $NAME..."
        start_daemon
        ;;
    reload)
        if test_daemon; then
            echo "Reloading $NAME..."
            reload_daemon
        else
            echo "$NAME is not running"
            exit 1
        fi
        ;;
    status)
        if test_daemon; then
            echo "$NAME is running"
            exit 0
        fi
        echo "$NAME is not running"
        exit 1
        ;;
    *)
        echo "usage: $0 {start|stop|restart|reload|status}" >&2
        exit 1
        ;;
esac

exit 0
