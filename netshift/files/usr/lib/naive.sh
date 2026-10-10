# shellcheck shell=ash
#
# NaiveProxy links: naive+https://user:pass@host[:port], naive+quic://..., or a
# plain https://user:pass@host[:port] (an https link with a login is a NaiveProxy
# server; a link without one is not).
#
# Two ways to carry them, the first that is possible is used:
#   1. the sing-box core has the `naive` outbound (sing-box 1.13+, built with the
#      with_naive_outbound tag and the Chromium network stack: only some builds,
#      such as the official musl ones);
#   2. the original `naive` client (klzgrad/naiveproxy, an OpenWrt build exists) runs
#      beside sing-box as a local SOCKS5 server and sing-box sends the traffic to it.
#      It works with any sing-box build. The clients are started by the
#      netshift-naive init script from a list the configuration builder writes.

NAIVE_PORT_BASE=19300
NAIVE_LIST_FILE="/tmp/netshift-naive.list"
NAIVE_RUNNING_FILE="/tmp/netshift-naive.running"
NAIVE_INIT="/etc/init.d/netshift-naive"

# Does the running core carry the naive outbound?
naive_core_supported() {
    command -v sing-box > /dev/null 2>&1 || return 1
    sing-box version 2> /dev/null | sed -n 's/^Tags: //p' | tr ',' '\n' | grep -qx 'with_naive_outbound'
}

# The path of the naive client, nothing when it is not installed.
naive_binary() {
    local candidate

    for candidate in "$(command -v naive 2> /dev/null)" /usr/bin/naive /usr/bin/naiveproxy /opt/bin/naive; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

# Is a naive client running? Matched by the path the init script started (the client
# may be installed as naive or naiveproxy), not by a fixed process name.
naive_running() {
    local binary

    binary="$(naive_binary)" || return 1
    pgrep -f "$binary --listen=socks://" > /dev/null 2>&1
}

# A new, empty list of clients: called when a configuration build starts.
naive_sidecars_reset() {
    : > "$NAIVE_LIST_FILE"
    : > "$NAIVE_LIST_FILE.urls"
    chmod 600 "$NAIVE_LIST_FILE" "$NAIVE_LIST_FILE.urls" 2> /dev/null
}

# Adds a client for a proxy URL ("https://user:pass@host:port" or "quic://...") and
# prints the local port that serves it. The same URL gets the same port again.
naive_register() {
    local proxy_url="$1"
    local line port count

    [ -f "$NAIVE_LIST_FILE" ] || naive_sidecars_reset

    line="$(grep -F -n -x -- "$proxy_url" "$NAIVE_LIST_FILE.urls" 2> /dev/null | sed -n '1p')"
    if [ -n "$line" ]; then
        printf '%s\n' "$((NAIVE_PORT_BASE + ${line%%:*} - 1))"
        return 0
    fi

    count="$(grep -c '' "$NAIVE_LIST_FILE.urls" 2> /dev/null)"
    count="${count:-0}"
    port=$((NAIVE_PORT_BASE + count))
    printf '%s\n' "$proxy_url" >> "$NAIVE_LIST_FILE.urls"
    printf '%s|%s\n' "$port" "$proxy_url" >> "$NAIVE_LIST_FILE"
    chmod 600 "$NAIVE_LIST_FILE" "$NAIVE_LIST_FILE.urls" 2> /dev/null
    printf '%s\n' "$port"
}

# Starts, restarts (the list changed) or stops the clients to match the list.
naive_sidecars_apply() {
    if [ ! -s "$NAIVE_LIST_FILE" ]; then
        naive_sidecars_stop
        return 0
    fi

    if cmp -s "$NAIVE_LIST_FILE" "$NAIVE_RUNNING_FILE" 2> /dev/null && naive_running; then
        return 0
    fi

    cp "$NAIVE_LIST_FILE" "$NAIVE_RUNNING_FILE"
    chmod 600 "$NAIVE_RUNNING_FILE" 2> /dev/null
    "$NAIVE_INIT" restart > /dev/null 2>&1 || log "Could not start the NaiveProxy clients" "error"
    # procd starts the clients in the background: a client that dies at once (a missing library,
    # a bad option) would otherwise show up only as a section that talks to a dead port
    sleep 1
    naive_running || log "The NaiveProxy client is not running after the start; see the system log (logread -e naive)" "error"
}

naive_sidecars_stop() {
    [ -x "$NAIVE_INIT" ] && "$NAIVE_INIT" stop > /dev/null 2>&1
    rm -f "$NAIVE_RUNNING_FILE"
    return 0
}
