#!/bin/bash
# shellcheck disable=SC1091

set -e

source /includes/colors.sh
source /includes/restapi.sh
source /includes/server.sh
source /includes/webhook.sh

function get_time() {
    date '+[%H:%M:%S]'
}

function check_for_update() {
    if [[ -z "${AUTO_UPDATE_ENABLED}" ]] || [[ "${AUTO_UPDATE_ENABLED,,}" != "true" ]]; then
        ei "> AUTO_UPDATE_ENABLED is not set to true. Exiting."
        exit 0
    fi

    ei ">>> Checking for Palworld server updates..."

    local latest_manifest current_manifest
    latest_manifest=$(curl -s --max-time 10 https://api.steamcmd.net/v1/info/2394010 | jq -r '.data["2394010"].depots["2394011"].manifests.public.gid // empty' 2>/dev/null)

    if [[ -z "$latest_manifest" || "$latest_manifest" == "null" ]]; then
        ew ">>> Failed to retrieve latest manifest from Steam API."
        if [[ -n $WEBHOOK_ENABLED ]] && [[ "${WEBHOOK_ENABLED,,}" == "true" ]]; then
            send_update_check_failed_notification
        fi
        exit 0
    fi

    local acf_file="${GAME_ROOT:-/palworld}/steamapps/appmanifest_2394010.acf"
    if [[ ! -f "$acf_file" ]]; then
        ew ">>> appmanifest_2394010.acf not found at '$acf_file'. Cannot compare versions."
        exit 0
    fi

    current_manifest=$(awk '/manifest/{count++} count==2 {print $2; exit}' "$acf_file" | tr -d '"')

    if [[ -z "$current_manifest" ]]; then
        ew ">>> Failed to read current manifest GID from appmanifest file."
        exit 0
    fi

    ei "> Current manifest: ${current_manifest}"
    ei "> Latest manifest:  ${latest_manifest}"

    if [[ "$current_manifest" == "$latest_manifest" ]]; then
        es "> Server is up to date."
        exit 0
    fi

    ew ">>> New update detected! Current: ${current_manifest}, Latest: ${latest_manifest}"
    request_manual_update_on_next_start

    if [[ -n $WEBHOOK_ENABLED ]] && [[ "${WEBHOOK_ENABLED,,}" == "true" ]]; then
        send_update_notification
    fi

    local countdown=15
    if [[ ${AUTO_UPDATE_COUNTDOWN} =~ ^[0-9]+$ ]]; then
        countdown=${AUTO_UPDATE_COUNTDOWN}
    fi

    if [[ -f "${GAME_ROOT:-/palworld}/PLAYER_DETECTION.PID" ]]; then
        export PLAYER_DETECTION_PID=$(<"${GAME_ROOT:-/palworld}/PLAYER_DETECTION.PID")
    fi

    for ((counter=$countdown; counter>=1; counter--)); do
        if [[ -n $RESTAPI_ENABLED ]] && [[ "${RESTAPI_ENABLED,,}" == "true" ]]; then
            if check_is_server_empty; then
                ew ">>> Server is empty, updating now"
                break
            else
                ew ">>> Server has still players"
            fi
            if [[ -n $AUTO_UPDATE_ANNOUNCE_MESSAGES_ENABLED ]] && [[ "${AUTO_UPDATE_ANNOUNCE_MESSAGES_ENABLED,,}" == "true" ]]; then
                restapi_announce "$(get_time) AUTOMATIC SERVER UPDATE AND RESTART IN $counter MINUTES"
            fi
        fi
        if [[ -n $AUTO_UPDATE_DEBUG_OVERRIDE ]] && [[ "${AUTO_UPDATE_DEBUG_OVERRIDE,,}" == "true" ]]; then
            sleep 1
        else
            sleep 60
        fi
    done

    if [[ -n $RESTAPI_ENABLED ]] && [[ "${RESTAPI_ENABLED,,}" == "true" ]]; then
        if [[ -n $AUTO_UPDATE_ANNOUNCE_MESSAGES_ENABLED ]] && [[ "${AUTO_UPDATE_ANNOUNCE_MESSAGES_ENABLED,,}" == "true" ]]; then
            restapi_announce "$(get_time) Saving world before update..."
            restapi_save
            restapi_announce "$(get_time) Saving done"
        else
            restapi_save
        fi
        sleep 15
        if [[ -n "${PLAYER_DETECTION_PID}" ]]; then
            kill -SIGTERM "${PLAYER_DETECTION_PID}" 2>/dev/null
        fi
        restapi_shutdown 10 "$(get_time) Server updating..."
        if [[ -n $WEBHOOK_ENABLED ]] && [[ "${WEBHOOK_ENABLED,,}" == "true" ]]; then
            send_stop_notification
        fi
    else
        stop_server
    fi
}

check_for_update
