# shellcheck disable=SC2148,SC1091

source /includes/colors.sh
source /includes/rcon.sh
source /includes/webhook.sh

wine_game_root=`winepath -w ${GAME_ROOT}`

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
    kill -SIGTERM "${PLAYER_DETECTION_PID}"
    if [[ -n $RCON_ENABLED ]] && [[ $RCON_ENABLED == "true" ]]; then
        save_and_shutdown_server
    fi
    kill -SIGTERM "$(pidof start.exe)"
    tail --pid="$(pidof start.exe)" -f 2>/dev/null
	if [[ -n $WEBHOOK_ENABLED ]] && [[ $WEBHOOK_ENABLED == "true" ]]; then
        send_stop_notification
    fi
    ew ">>> Server stopped gracefully"
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
