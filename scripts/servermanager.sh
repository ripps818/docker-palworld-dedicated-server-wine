#!/bin/bash
# shellcheck disable=SC1091
# IF Bash extension used:
# https://stackoverflow.com/a/13864829
# https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_06_02

set -e

# Setup Wine it doesn't exist
if [ ! -d "${WINEPREFIX}" ]; then
	echo -ne "\e[94m>>> Initializing Wine configuration\e[0m"
	echo ""
	WINEDLLOVERRIDES="mscoree,mshtml=" wineboot --init && wineserver -w
fi

source /includes/colors.sh
source /includes/config.sh
source /includes/cron.sh
source /includes/playerdetection.sh
source /includes/security.sh
source /includes/server.sh
source /includes/webhook.sh

START_MAIN_PID=
PLAYER_DETECTION_PID=



# Handler for SIGTERM from docker-based stop events
function term_handler() {
    stop_server
}

# Main process thread
function start_main() {
    check_for_default_credentials
    check_for_deprecated_variables
	if [ "${WINETRICK_ON_START}" == "true" ]; then
		winetricks_install
	fi
    if [ ! -f "${GAME_BIN}" ]; then
        fresh_install_server
    fi
    if [ "$ALWAYS_UPDATE_ON_START" = "true" ] || manual_update_requested; then
        update_server
        disable_manual_update_on_next_start
    fi
	echo "${GAME_BIN}"
    setup_crons
    start_server
}

# Bash-Trap for exit signals to handle
trap 'term_handler' SIGTERM

# Main process loop
while true
do
    current_date=$(date +%Y-%m-%d)
    current_time=$(date +%H:%M:%S)
    ei ">>> Starting server manager"
    e "> Started at: $current_date $current_time"
    start_main &
    START_MAIN_PID="$!"

    if [[ -n $RCON_PLAYER_DETECTION ]] && [[ $RCON_PLAYER_DETECTION == "true" ]] && [[ -n $RCON_ENABLED ]] && [[ $RCON_ENABLED == "true" ]]; then
       player_detection_loop &
       PLAYER_DETECTION_PID="$!"
       echo "${PLAYER_DETECTION_PID}" > "${GAME_ROOT}/PLAYER_DETECTION.PID"
       ew "> Player detection thread started with pid ${PLAYER_DETECTION_PID}"
    fi

    ew "> Server main thread started with pid ${START_MAIN_PID}"
    wait ${START_MAIN_PID}

    if [[ -n $WEBHOOK_ENABLED ]] && [[ $WEBHOOK_ENABLED == "true" ]]; then
        send_stop_notification
    fi
    exit 0;
done
