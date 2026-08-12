# shellcheck disable=SC2148,SC1091
#
# AUTO_PAUSE: SIGSTOPs the gameserver when idle for AUTO_PAUSE_TIMEOUT seconds,
# SIGCONTs it on an incoming connection (autopause-monitor.sh) or any REST API
# call (resume hook in restapi.sh), so backups/announces/restarts wake it
# transparently.
#
# State lives in files under ${GAME_ROOT}/.autopause/, not shell variables,
# since the pause is owned by player_detection_loop but must be
# observable/triggerable from other processes (restart.sh, the CLI, the
# monitor).
#
# Sourced into scripts running under `set -e` and called as a bare statement
# from player_detection_loop's main loop - any unguarded failing command here
# would silently kill that background loop. Every function always returns 0
# and guards risky commands with `|| true`.

source /includes/colors.sh

AUTOPAUSE_STATE_DIR="${GAME_ROOT:-/palworld}/.autopause"
AUTOPAUSE_PAUSE_FILE="${AUTOPAUSE_STATE_DIR}/paused"
AUTOPAUSE_REQUEST_FILE="${AUTOPAUSE_STATE_DIR}/resume-request"
AUTOPAUSE_DISABLE_FILE="${AUTOPAUSE_STATE_DIR}/force-disabled"
AUTOPAUSE_MONITOR_PIDFILE="${AUTOPAUSE_STATE_DIR}/monitor.pid"

declare -i AUTOPAUSE_IDLE_SECONDS=0

# [HH:MM:SS] prefix - Docker's own log timestamp is always UTC regardless of
# container TZ, so this is what shows local time.
function autopause_ts() {
    date '+[%H:%M:%S]'
}

function autopause_is_enabled() {
    if [[ -z $AUTO_PAUSE_ENABLED ]] || [[ "${AUTO_PAUSE_ENABLED,,}" != "true" ]]; then
        return 1
    fi
    if [[ -z $PLAYER_DETECTION_ENABLED ]] || [[ "${PLAYER_DETECTION_ENABLED,,}" != "true" ]] || \
       [[ -z $RESTAPI_ENABLED ]] || [[ "${RESTAPI_ENABLED,,}" != "true" ]]; then
        ew "$(autopause_ts) >>> AUTO_PAUSE_ENABLED requires PLAYER_DETECTION_ENABLED=true and RESTAPI_ENABLED=true. Auto-pause disabled."
        return 1
    fi
    return 0
}

function autopause_is_paused() {
    [[ -f "${AUTOPAUSE_PAUSE_FILE}" ]]
}

function autopause_is_force_disabled() {
    [[ -f "${AUTOPAUSE_DISABLE_FILE}" ]]
}

# True only if every PID matching the executable is in state T (stopped).
function autopause_process_is_stopped() {
    local server_executable
    server_executable=$(basename "${GAME_BIN}")

    local -i total stopped
    total=$(pgrep -f "${server_executable}" 2>/dev/null | wc -l)
    stopped=$(pgrep -r T -f "${server_executable}" 2>/dev/null | wc -l)

    [[ "${total}" -gt 0 ]] && [[ "${total}" -eq "${stopped}" ]]
}

# Clears stale state from a previous container run.
function autopause_init() {
    mkdir -p "${AUTOPAUSE_STATE_DIR}" 2>/dev/null || true
    autopause_is_enabled || return 0
    rm -f "${AUTOPAUSE_PAUSE_FILE}" "${AUTOPAUSE_REQUEST_FILE}" "${AUTOPAUSE_DISABLE_FILE}" "${AUTOPAUSE_MONITOR_PIDFILE}"
    AUTOPAUSE_IDLE_SECONDS=0

    local server_executable
    server_executable=$(basename "${GAME_BIN}")
    ei "$(autopause_ts) >>> AUTO_PAUSE enabled (timeout=${AUTO_PAUSE_TIMEOUT:-180}s, matching '${server_executable}')"
    return 0
}

# Leaves a resume request on disk for the paused wait loop to pick up.
function autopause_request_resume() {
    local reason="${1:-unknown}"
    echo "${reason}" > "${AUTOPAUSE_REQUEST_FILE}" 2>/dev/null || true
    return 0
}

# Called every PLAYER_DETECTION_CHECK_INTERVAL with the current player count;
# pauses once idle for AUTO_PAUSE_TIMEOUT.
function autopause_tick() {
    autopause_is_enabled || return 0
    local -i count="${1:-0}"

    if [[ "${count}" -gt 0 ]]; then
        AUTOPAUSE_IDLE_SECONDS=0
        return 0
    fi

    if autopause_is_paused; then
        return 0
    fi

    if autopause_is_force_disabled; then
        return 0
    fi

    AUTOPAUSE_IDLE_SECONDS+=${PLAYER_DETECTION_CHECK_INTERVAL:-15}
    if [[ "${AUTOPAUSE_IDLE_SECONDS}" -ge "${AUTO_PAUSE_TIMEOUT:-180}" ]]; then
        autopause_pause || true
    fi
    return 0
}

# Saves, freezes the process, starts the wake monitor, blocks until resumed.
# Returns 1 if aborted (process missing / save failed) - not fatal, retried
# next tick.
function autopause_pause() {
    if autopause_is_paused; then
        return 0
    fi

    local server_executable
    server_executable=$(basename "${GAME_BIN}")
    if ! pgrep -f "${server_executable}" >/dev/null; then
        ew "$(autopause_ts) > AUTO_PAUSE: server process not found, skipping pause attempt"
        return 1
    fi

    # Already stopped (drift) - sync state, skip save/signal.
    if autopause_process_is_stopped; then
        ei "$(autopause_ts) >>> AUTO_PAUSE: process already stopped, syncing state without re-signaling"
        touch "${AUTOPAUSE_PAUSE_FILE}" 2>/dev/null || true
        rm -f "${AUTOPAUSE_REQUEST_FILE}"
        autopause_monitor_start || true
        autopause_wait_for_wake || true
        return 0
    fi

    ei "$(autopause_ts) >>> AUTO_PAUSE: server idle for ${AUTOPAUSE_IDLE_SECONDS}s, saving world before pausing..."
    if ! restapi_save; then
        ew "$(autopause_ts) > AUTO_PAUSE: save failed, aborting pause attempt (will retry next tick)"
        return 1
    fi

    # SIGSTOP only the top PID would miss the actual engine process (Wine
    # wraps it in script/start.exe) - signal every matching PID instead.
    ei "$(autopause_ts) >>> AUTO_PAUSE: pausing server"
    pkill -STOP -f "${server_executable}" 2>/dev/null || true
    touch "${AUTOPAUSE_PAUSE_FILE}" 2>/dev/null || true
    rm -f "${AUTOPAUSE_REQUEST_FILE}"
    autopause_monitor_start || true

    autopause_wait_for_wake || true
    return 0
}

# Blocks until a resume is requested (REST call, monitor, or manual CLI).
function autopause_wait_for_wake() {
    local -i pulse_timer=0
    local -i pulse_interval="${AUTO_PAUSE_HEARTBEAT_INTERVAL:-90}"
    local -i pulse_duration="${AUTO_PAUSE_HEARTBEAT_DURATION:-4}"
    local server_executable
    server_executable=$(basename "${GAME_BIN}")

    while autopause_is_paused; do
        if [[ -f "${AUTOPAUSE_REQUEST_FILE}" ]]; then
            break
        fi

        # Micro-unpause heartbeat pulse for Community Server master list keepalive
        if [[ "${COMMUNITY_SERVER,,}" == "true" ]] || [[ "${AUTO_PAUSE_HEARTBEAT_PULSE,,}" == "true" ]]; then
            pulse_timer+=1
            if [[ ${pulse_timer} -ge ${pulse_interval} ]]; then
                if [[ "${AUTO_PAUSE_LOG,,}" == "true" ]]; then
                    ei "$(autopause_ts) >>> AUTO_PAUSE: sending micro-unpause heartbeat pulse (${pulse_duration}s)"
                fi
                pkill -CONT -f "${server_executable}" 2>/dev/null || true
                sleep "${pulse_duration}"
                if autopause_is_paused && [[ ! -f "${AUTOPAUSE_REQUEST_FILE}" ]]; then
                    pkill -STOP -f "${server_executable}" 2>/dev/null || true
                fi
                pulse_timer=0
            fi
        fi

        sleep 1
    done
    autopause_resume || true
    return 0
}

function autopause_resume() {
    if ! autopause_is_paused; then
        return 0
    fi

    autopause_monitor_stop || true

    local server_executable
    server_executable=$(basename "${GAME_BIN}")
    if ! pgrep -f "${server_executable}" >/dev/null; then
        ew "$(autopause_ts) > AUTO_PAUSE: server process not found while resuming"
    elif autopause_process_is_stopped; then
        pkill -CONT -f "${server_executable}" 2>/dev/null || true
        ei "$(autopause_ts) >>> AUTO_PAUSE: server resumed"
    else
        ei "$(autopause_ts) >>> AUTO_PAUSE: process already running, skipping redundant SIGCONT"
    fi

    rm -f "${AUTOPAUSE_PAUSE_FILE}" "${AUTOPAUSE_REQUEST_FILE}"
    AUTOPAUSE_IDLE_SECONDS=0
    return 0
}

# Called from restapi_get()/restapi_post() so every REST consumer
# transparently wakes a paused server first.
function autopause_resume_and_wait() {
    autopause_is_enabled || return 0
    autopause_is_paused || return 0

    autopause_request_resume "REST API call"

    local -i waited=0
    local -i timeout="${AUTOPAUSE_RESUME_TIMEOUT:-30}"
    while autopause_is_paused && [[ ${waited} -lt ${timeout} ]]; do
        sleep 1
        waited+=1
    done

    if autopause_is_paused; then
        ew "$(autopause_ts) > AUTO_PAUSE: timed out after ${timeout}s waiting for server to resume"
        return 1
    fi
    return 0
}

# Used by restart.sh so a restart countdown can't be interrupted by re-pausing.
function autopause_disable() {
    touch "${AUTOPAUSE_DISABLE_FILE}" 2>/dev/null || true
    if autopause_is_paused; then
        autopause_request_resume "force-disabled"
    fi
    return 0
}

function autopause_enable() {
    rm -f "${AUTOPAUSE_DISABLE_FILE}"
    return 0
}
