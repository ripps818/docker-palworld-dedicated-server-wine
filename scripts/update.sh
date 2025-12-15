#!/bin/bash

set -e

source /includes/colors.sh
source /includes/server.sh
source /includes/webhook.sh

function get_time() {
  date '+[%H:%M:%S]'
}

function start_update_check() {
  ew ">>> Automatic update check was triggered..."
  if [[ -f "${GAME_ROOT}/PLAYER_DETECTION.PID" ]]; then
    export PLAYER_DETECTION_PID=$(<"${GAME_ROOT}/PLAYER_DETECTION.PID")
  fi

  local temp_file http_code latest_manifest current_manifest countdown updateAvailable

  temp_file=$(mktemp)
  http_code=$(curl https://api.steamcmd.net/v1/info/2394010 --output "$temp_file" --silent --location --write-out "%{http_code}")

  if [ "$http_code" -ne 200 ]; then
    ee "There was a problem reaching the Steam api, unable to check for updates"
    if [[ -n $WEBHOOK_ENABLED ]] && [[ $WEBHOOK_ENABLED == "true" ]]; then
      send_update_check_failed_notification
    fi
    rm "$temp_file"
    return 2
  fi

  latest_manifest=$(jq -r '.data["2394010"].depots["2394011"].manifests.public.gid' $temp_file)
  rm "$temp_file"

  current_manifest=$(awk '/manifest/{count++} count==2 {print $2; exit}' /palworld/steamapps/appmanifest_2394010.acf | tr -d '"')
  ei "Current version: $current_manifest"

  updateAvailable=false
  if [ "$current_manifest" != "$latest_manifest" ]; then
    ei "An update is available. Latest version: $latest_manifest."
    updateAvailable=true
  fi

  if [ "$updateAvailable" == false ]; then
    es "The server is up to date"
    return 0
  fi

  if [[ $AUTO_UPDATE_COUNTDOWN =~ ^[0-9]+$ ]]; then
    ei "> Auto update countdown set to $AUTO_UPDATE_COUNTDOWN minutes"
    countdown=$AUTO_UPDATE_COUNTDOWN
  else
    ew ">> AUTO_UPDATE_COUNTDOWN value invalid, setting countdown to 15 minutes"
    countdown=15
  fi

  for ((counter=$countdown; counter>=1; counter--)); do
    if [[ -n $RCON_ENABLED ]] && [[ $RCON_ENABLED == "true" ]]; then
      if check_is_server_empty; then
          ew ">>> Server is empty, updating now"
          if [[ -n $WEBHOOK_ENABLED ]] && [[ $WEBHOOK_ENABLED == "true" ]]; then
              send_update_notification
          fi
          break
      else
          ew ">>> Server still has players"
      fi
      if [[ -n $AUTO_UPDATE_ANNOUNCE_MESSAGES_ENABLED ]] && [[ $AUTO_UPDATE_ANNOUNCE_MESSAGES_ENABLED == "true" ]]; then
        rconcli "broadcast $(get_time) AUTOMATIC SERVER UPDATE AND RESTART IN $counter MINUTES"
      fi
    fi
    if [[ -n $AUTO_UPDATE_DEBUG_OVERRIDE ]] && [[ $AUTO_UPDATE_DEBUG_OVERRIDE == "true" ]]; then
        sleep 1
    else
        sleep 60
    fi
  done

  if [[ -n $RCON_ENABLED ]] && [[ $RCON_ENABLED == "true" ]]; then
    if [[ -n $RESTART_ANNOUNCE_MESSAGES_ENABLED ]] && [[ $RESTART_ANNOUNCE_MESSAGES_ENABLED == "true" ]]; then
      rconcli "broadcast $(get_time) Saving world before update and restart..."
    fi
    rconcli 'save'
    if [[ -n $RESTART_ANNOUNCE_MESSAGES_ENABLED ]] && [[ $RESTART_ANNOUNCE_MESSAGES_ENABLED == "true" ]]; then
      rconcli "broadcast $(get_time) Saving done"
    fi
    sleep 15

    request_manual_update_on_next_start

    if [[ -n "${PLAYER_DETECTION_PID}" ]]; then
      kill -SIGTERM "${PLAYER_DETECTION_PID}"
    fi
    rconcli "Shutdown 10"
    if [[ -n $WEBHOOK_ENABLED ]] && [[ $WEBHOOK_ENABLED == "true" ]]; then
        send_stop_notification
    fi
  else
      stop_server
  fi
}

start_update_check
