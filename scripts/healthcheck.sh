#!/bin/bash
# shellcheck disable=SC1091

source /includes/config.sh

# Paused (AUTO_PAUSE) servers can't answer REST - not unhealthy, safe no-op if absent.
if [[ -f "${GAME_ROOT:-/palworld}/.autopause/paused" ]]; then
    exit 0
fi

# REST API disabled - fall back to plain process-existence check.
if [[ -z $RESTAPI_ENABLED ]] || [[ "${RESTAPI_ENABLED,,}" != "true" ]]; then
    server_executable=$(basename "${GAME_BIN:-/palworld/Pal/Binaries/Win64/PalServer-Win64-Shipping-Cmd.exe}")
    pgrep -f "${server_executable}" >/dev/null 2>&1
    exit $?
fi

admin_password=$(get_admin_password)
curl -sf -o /dev/null --max-time 5 \
    -u "admin:${admin_password}" \
    "http://127.0.0.1:${RESTAPI_PORT:-8212}/v1/api/info"
