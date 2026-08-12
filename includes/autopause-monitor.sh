# shellcheck disable=SC2148,SC1091
#
# Wake-on-connect backend for AUTO_PAUSE: a SIGSTOP'd process can't respond to
# anything, so detecting an incoming player needs out-of-band packet capture
# (NFLOG via iptables + tcpdump), which needs NET_ADMIN - see compose.yml.
#
# Sourced into scripts running under `set -e`; every command here is
# best-effort and guarded with `|| true`.

source /includes/colors.sh

AUTOPAUSE_NFLOG_GROUP="${AUTOPAUSE_NFLOG_GROUP:-100}"

function autopause_monitor_interface() {
    local iface="${AUTO_PAUSE_KNOCKD_IF:-}"
    if [[ -z "${iface}" ]]; then
        iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
    fi
    echo "${iface}"
}

# Ports to watch: game UDP and REST API TCP. Game port is always 8211 - this
# image has no -port= launch flag, so PUBLIC_PORT (the ini's advertised port,
# can differ behind a tunnel/NAT) is not the same thing as the real listener.
function autopause_monitor_watch_ports() {
    echo "8211/udp ${RESTAPI_PORT:-8212}/tcp"
}

function autopause_monitor_start() {
    local iface
    iface=$(autopause_monitor_interface)
    if [[ -z "${iface}" ]]; then
        ew "$(autopause_ts) > AUTO_PAUSE monitor: could not determine network interface (set AUTO_PAUSE_KNOCKD_IF), server will only wake on REST API activity"
        return 1
    fi

    if ! command -v iptables >/dev/null 2>&1 || ! command -v tcpdump >/dev/null 2>&1; then
        ew "$(autopause_ts) > AUTO_PAUSE monitor: iptables/tcpdump not available, server will only wake on REST API activity"
        return 1
    fi

    local port_proto port proto
    for port_proto in $(autopause_monitor_watch_ports); do
        port="${port_proto%/*}"
        proto="${port_proto#*/}"
        iptables -I INPUT -i "${iface}" -p "${proto}" --dport "${port}" -j NFLOG --nflog-group "${AUTOPAUSE_NFLOG_GROUP}" 2>/dev/null || true
    done

    (
        if tcpdump -i "nflog:${AUTOPAUSE_NFLOG_GROUP}" -n -c 1 >/dev/null 2>&1; then
            if [[ -n $AUTO_PAUSE_LOG ]] && [[ "${AUTO_PAUSE_LOG,,}" == "true" ]]; then
                ei "$(autopause_ts) > AUTO_PAUSE monitor: incoming connection detected"
            fi
            autopause_request_resume "incoming connection detected"
        else
            ew "$(autopause_ts) > AUTO_PAUSE monitor: tcpdump failed (missing NET_ADMIN?), this cycle will only wake on REST API activity"
        fi
    ) &
    echo "$!" > "${AUTOPAUSE_MONITOR_PIDFILE}" 2>/dev/null || true

    if [[ -n $AUTO_PAUSE_LOG ]] && [[ "${AUTO_PAUSE_LOG,,}" == "true" ]]; then
        ei "$(autopause_ts) > AUTO_PAUSE monitor: watching ${iface} for $(autopause_monitor_watch_ports)"
    fi
    return 0
}

function autopause_monitor_stop() {
    if [[ -f "${AUTOPAUSE_MONITOR_PIDFILE}" ]]; then
        local pid
        pid=$(<"${AUTOPAUSE_MONITOR_PIDFILE}") 2>/dev/null || true
        if [[ -n "${pid}" ]]; then
            # Not `wait`-ing: the PID may not be this process's child (resume
            # can run from a different invocation than the one that paused),
            # and `wait` on a non-child fails hard under `set -e`.
            pkill -P "${pid}" 2>/dev/null || true
            kill "${pid}" 2>/dev/null || true
        fi
        rm -f "${AUTOPAUSE_MONITOR_PIDFILE}"
    fi

    local iface
    iface=$(autopause_monitor_interface)
    if [[ -n "${iface}" ]] && command -v iptables >/dev/null 2>&1; then
        local port_proto port proto
        for port_proto in $(autopause_monitor_watch_ports); do
            port="${port_proto%/*}"
            proto="${port_proto#*/}"
            iptables -D INPUT -i "${iface}" -p "${proto}" --dport "${port}" -j NFLOG --nflog-group "${AUTOPAUSE_NFLOG_GROUP}" 2>/dev/null || true
        done
    fi
    return 0
}
