# shellcheck disable=SC2148

APP_HOME=/home/steam

# Start supercronic and load crons
function setup_crons() {
    if [[ -f "$APP_HOME/supercronic.pid" ]]; then
        local old_pid
        old_pid=$(cat "$APP_HOME/supercronic.pid" 2>/dev/null || true)
        if [[ -n "$old_pid" ]]; then
            kill "$old_pid" 2>/dev/null || pkill -f supercronic 2>/dev/null || true
        else
            pkill -f supercronic 2>/dev/null || true
        fi
        rm -f "$APP_HOME/supercronic.pid"
    else
        pkill -f supercronic 2>/dev/null || true
    fi

    echo "" > $APP_HOME/cronlist    
    ei ">>> Adding crons to Supercronic"
    if [[ -n ${BACKUP_ENABLED} ]] && [[ ${BACKUP_ENABLED} == "true" ]]; then
        echo "${BACKUP_CRON_EXPRESSION} backup create" >> $APP_HOME/cronlist
        e "> Added backup cron"
    fi
    if [[ -n ${RESTART_ENABLED} ]] && [[ ${RESTART_ENABLED} == "true" ]]; then
        echo "${RESTART_CRON_EXPRESSION} restart" >> $APP_HOME/cronlist
        e "> Added restart cron"
    fi
    if [[ -n ${AUTO_UPDATE_ENABLED} ]] && [[ ${AUTO_UPDATE_ENABLED} == "true" ]]; then
      echo "${AUTO_UPDATE_CRON_EXPRESSION} update" >> $APP_HOME/cronlist
      e "> Added auto-update cron"
    fi
    if [[ -n ${WORKSHOP_MOD_UPDATE_CRON:-} ]]; then
        echo "${WORKSHOP_MOD_UPDATE_CRON} /scripts/install-mods.sh" >> $APP_HOME/cronlist
        e "> Added workshop mods auto-update cron"
    fi
    /usr/local/bin/supercronic -passthrough-logs $APP_HOME/cronlist &
    echo "$!" > "$APP_HOME/supercronic.pid"
    es ">>> Supercronic started"
}
