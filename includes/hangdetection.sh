# shellcheck disable=SC2148,SC1091
#
# HANG_DETECTION: kills the gameserver process if it stops answering REST
# calls for HANG_DETECTION_THRESHOLD consecutive polls, letting
# servermanager.sh's existing restart-on-exit loop recover it - same
# mechanism as an ordinary crash, no Docker API needed.
#
# Never acts until the first successful check - a fixed startup delay can't
# safely guess install time, so a slow-but-fine first boot must not get
# killed. HANG_DETECTION_FIRST_SUCCESS_TIMEOUT is the backstop for the
# opposite case: alive but genuinely stuck before ever succeeding once.
#
# Suspended whenever ${GAME_ROOT}/.stopping exists, so it never competes
# with an intentional stop/restart already in progress.

source /includes/colors.sh

function hangdetect_ts() {
    date '+[%H:%M:%S]'
}

function hangdetect_is_enabled() {
    if [[ -z $HANG_DETECTION_ENABLED ]] || [[ "${HANG_DETECTION_ENABLED,,}" != "true" ]]; then
        return 1
    fi
    if [[ -z $RESTAPI_ENABLED ]] || [[ "${RESTAPI_ENABLED,,}" != "true" ]]; then
        ew "$(hangdetect_ts) >>> HANG_DETECTION_ENABLED requires RESTAPI_ENABLED=true. Hang detection disabled."
        return 1
    fi
    return 0
}

function hangdetect_is_stopping() {
    [[ -f "${GAME_ROOT:-/palworld}/.stopping" ]]
}

function hangdetect_loop() {
    hangdetect_is_enabled || return 0

    local -i misses=0
    local -i seen_healthy=0
    local -i threshold="${HANG_DETECTION_THRESHOLD:-3}"
    local -i interval="${HANG_DETECTION_INTERVAL:-30}"
    local -i first_success_timeout="${HANG_DETECTION_FIRST_SUCCESS_TIMEOUT:-1800}"
    local -i loop_start
    loop_start=$(date +%s)

    while true; do
        sleep "${interval}"

        if hangdetect_is_stopping; then
            misses=0
            continue
        fi

        if /scripts/healthcheck.sh; then
            misses=0
            seen_healthy=1
            continue
        fi

        local -i should_restart=0

        if [[ "${seen_healthy}" -eq 0 ]]; then
            local -i elapsed=$(( $(date +%s) - loop_start ))
            if [[ "${elapsed}" -ge "${first_success_timeout}" ]]; then
                ee "$(hangdetect_ts) >>> HANG_DETECTION: never became responsive after ${first_success_timeout}s, forcing restart"
                should_restart=1
            fi
        else
            misses+=1
            ew "$(hangdetect_ts) > HANG_DETECTION: unresponsive (${misses}/${threshold})"
            if [[ "${misses}" -ge "${threshold}" ]]; then
                ee "$(hangdetect_ts) >>> HANG_DETECTION: unresponsive for $((interval * threshold))s, forcing restart"
                should_restart=1
            fi
        fi

        # Re-check right before acting - a stop may have started during the healthcheck call above.
        if [[ "${should_restart}" -eq 1 ]] && ! hangdetect_is_stopping; then
            local server_executable
            server_executable=$(basename "${GAME_BIN:-/palworld/Pal/Binaries/Win64/PalServer-Win64-Shipping-Cmd.exe}")
            pkill -f -SIGKILL "${server_executable}" 2>/dev/null || true
            misses=0
            seen_healthy=0
            loop_start=$(date +%s)
        fi
    done
}
