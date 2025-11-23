# shellcheck disable=SC2148,SC1091

source /includes/colors.sh
source /includes/rcon.sh
source /includes/webhook.sh

wine_game_root=`winepath -w ${GAME_ROOT}`

function manual_update_requested() {
    if [[ -f "${GAME_ROOT}/.update_requested" ]]; then
      return 0
    fi

    return 1
}

function request_manual_update_on_next_start() {
    touch "${GAME_ROOT}/.update_requested"
}

function disable_manual_update_on_next_start() {
  rm -f "${GAME_ROOT}/.update_requested"
}

function start_server() {
    cd "$GAME_ROOT" || exit
    setup_configs
    ei ">>> Preparing to start the gameserver"
    START_OPTIONS=()
    if [[ -n $COMMUNITY_SERVER ]] && [[ $COMMUNITY_SERVER == "true" ]]; then
        e "> Setting Community-Mode to enabled"
        START_OPTIONS+=("-publiclobby")
    fi
    if [[ -n $MULTITHREAD_ENABLED ]] && [[ $MULTITHREAD_ENABLED == "true" ]]; then
        e "> Setting Multi-Core-Enhancements to enabled"
        START_OPTIONS+=("-useperfthreads" "-NoAsyncLoadingThread" "-UseMultithreadForDS")
    fi
    if [[ -n $WEBHOOK_ENABLED ]] && [[ $WEBHOOK_ENABLED == "true" ]]; then
        send_start_notification
    fi
    es ">>> Starting the gameserver"
    "${WINE_BIN}" "${GAME_BIN}" "${START_OPTIONS[@]}"
}

function stop_server() {
    ew ">>> Stopping server..."
    kill -SIGTERM "${PLAYER_DETECTION_PID}" 2>/dev/null

    local server_executable
    server_executable=$(basename "${GAME_BIN}")
    local killed=false

    # Check if server is running
    if ! pgrep -f "${server_executable}" > /dev/null; then
        ew ">>> Server process not found."
    else
        # Stage 1: RCON
        if [[ -n $RCON_ENABLED ]] && [[ $RCON_ENABLED == "true" ]]; then
            ew ">>> Attempting graceful shutdown via RCON..."
            save_and_shutdown_server
            ew ">>> Waiting up to 20 seconds for server to shut down..."
            for i in {1..20}; do
                if ! pgrep -f "${server_executable}" > /dev/null; then
                    break
                fi
                sleep 1
            done
        fi
    fi

    # Stage 2: wine taskkill (graceful)
    if pgrep -f "${server_executable}" > /dev/null; then
        ew ">>> RCON shutdown timed out or was skipped. Attempting shutdown via wine taskkill..."
        wine taskkill /im "${server_executable}" >/dev/null 2>&1
        ew ">>> Waiting up to 10 seconds for server to shut down..."
        for i in {1..10}; do
            if ! pgrep -f "${server_executable}" > /dev/null; then
                break
            fi
            sleep 1
        done
    fi

    # Stage 3: SIGTERM
    if pgrep -f "${server_executable}" > /dev/null; then
        ew ">>> wine taskkill timed out. Sending SIGTERM to server process..."
        pkill -f -SIGTERM "${server_executable}"
        ew ">>> Waiting up to 10 seconds for server to shut down..."
        for i in {1..10}; do
            if ! pgrep -f "${server_executable}" > /dev/null; then
                break
            fi
            sleep 1
        done
    fi

    # Stage 4: SIGKILL
    if pgrep -f "${server_executable}" > /dev/null; then
        ew ">>> Server process did not respond to SIGTERM. Sending SIGKILL (force kill)."
        pkill -f -SIGKILL "${server_executable}"
        killed=true
        sleep 2
    fi

    if [[ -n $WEBHOOK_ENABLED ]] && [[ $WEBHOOK_ENABLED == "true" ]]; then
        send_stop_notification
    fi

    if [[ "$killed" == "true" ]]; then
        ew ">>> Server stopped by force (SIGKILL)."
    else
        ew ">>> Server stopped gracefully."
    fi
    exit 143;
}

function fresh_install_server() {
    ei ">>> Doing a fresh install of the gameserver..."
    if [[ -n $WEBHOOK_ENABLED ]] && [[ $WEBHOOK_ENABLED == "true" ]]; then
        send_install_notification
    fi
    "${WINE_BIN}" "${STEAMCMD_PATH}"/steamcmd.exe +force_install_dir "${wine_game_root}" +login anonymous +app_update 2394010 validate +quit
    es "> Done installing the gameserver"
}

function update_server() {
    # Workaround fix for 0x6 error
    ei ">>> Applying workaround fix for 'Error! App '2394010' state is 0x6 after update job.' message, since update 0.3.X..."
    rm -f /palworld/steamapps/appmanifest_2394010.acf
    if [[ -n $STEAMCMD_VALIDATE_FILES ]] && [[ $STEAMCMD_VALIDATE_FILES == "true" ]]; then
        ei ">>> Doing an update with validation of the gameserver files..."
        if [[ -n $WEBHOOK_ENABLED ]] && [[ $WEBHOOK_ENABLED == "true" ]]; then
            send_update_notification
        fi
        "${WINE_BIN}" "${STEAMCMD_PATH}"/steamcmd.exe +force_install_dir "${wine_game_root}" +login anonymous +app_update 2394010 validate +quit
        es ">>> Done updating and validating the gameserver files"
    else
        ei ">>> Doing an update of the gameserver files..."
        if [[ -n $WEBHOOK_ENABLED ]] && [[ $WEBHOOK_ENABLED == "true" ]]; then
            send_update_notification
        fi
        "${WINE_BIN}" "${STEAMCMD_PATH}"/steamcmd.exe +force_install_dir "${wine_game_root}" +login anonymous +app_update 2394010 +quit
        es ">>> Done updating the gameserver files"
    fi
}

function winetricks_install() {
	ei ">>> Installing Visual C++ Runtime 2022"
	trickscmd=("${WINETRICK_BIN}")
	trickscmd+=("--optout" "-f" "-q" "vcrun2022")
	echo "${trickscmd[*]}"
	"${trickscmd[@]}"
}
