# shellcheck disable=SC2148,SC1091

source /includes/colors.sh

function check_for_default_credentials() {
    e "> Checking for existence of default credentials"
    if [[ -n $ADMIN_PASSWORD ]] && [[ $ADMIN_PASSWORD == "adminPasswordHere" ]]; then
        ee ">>> Security threat detected: Please change the default admin password. Aborting server start ..."
        exit 1
    fi
    if [[ -n $SERVER_PASSWORD ]] && [[ $SERVER_PASSWORD == "serverPasswordHere" ]]; then
        ee ">>> Security threat detected: Please change the default server password. Aborting server start ..."
        exit 1
    fi
    es "> No default passwords found"
}

function check_for_deprecated_variables() {
    e "> Checking for deprecated variables..."
    local deprecated_found=false
    if [[ -n ${RCON_QUIET_RESTART+x} ]]; then
        ew ">>> WARNING: The environment variable 'RCON_QUIET_RESTART' is deprecated and will be removed in a future version."
        ew ">>> Please use 'RESTART_ANNOUNCE_MESSAGES_ENABLED' instead."
        deprecated_found=true
        if [[ "$RCON_QUIET_RESTART" == "true" ]]; then
            export RESTART_ANNOUNCE_MESSAGES_ENABLED="false"
        else
            export RESTART_ANNOUNCE_MESSAGES_ENABLED="true"
        fi
    fi
    if [[ -n ${RCON_QUIET_BACKUP+x} ]]; then
        ew ">>> WARNING: The environment variable 'RCON_QUIET_BACKUP' is deprecated and will be removed in a future version."
        ew ">>> Please use 'BACKUP_ANNOUNCE_MESSAGES_ENABLED' instead."
        deprecated_found=true
        if [[ "$RCON_QUIET_BACKUP" == "true" ]]; then
            export BACKUP_ANNOUNCE_MESSAGES_ENABLED="false"
        else
            export BACKUP_ANNOUNCE_MESSAGES_ENABLED="true"
        fi
    fi
    if [[ -n ${RCON_QUIET_SAVE+x} ]]; then
        ew ">>> WARNING: The environment variable 'RCON_QUIET_SAVE' is deprecated and will be removed in a future version."
        ew ">>> Please use 'BACKUP_ANNOUNCE_MESSAGES_ENABLED' instead."
        deprecated_found=true
        # RCON_QUIET_SAVE=true meant no save announcements. This now maps to no backup announcements.
        if [[ "$RCON_QUIET_SAVE" == "true" ]]; then
            export BACKUP_ANNOUNCE_MESSAGES_ENABLED="false"
        else
            export BACKUP_ANNOUNCE_MESSAGES_ENABLED="true"
        fi
    fi

    if [[ "$deprecated_found" == "false" ]]; then
        es "> No deprecated variables found"
    fi
}
