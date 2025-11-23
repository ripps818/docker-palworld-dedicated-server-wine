# shellcheck disable=SC2148

APP_HOME=/home/steam

# Start supercronic and load crons
function setup_crons() {
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
    /usr/local/bin/supercronic -passthrough-logs $APP_HOME/cronlist &
    es ">>> Supercronic started"
}
