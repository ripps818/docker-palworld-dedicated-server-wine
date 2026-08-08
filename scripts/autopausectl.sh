#!/bin/bash
# shellcheck disable=SC1091

source /includes/colors.sh
source /includes/config.sh
source /includes/restapi.sh
source /includes/autopause.sh

function print_usage() {
    echo "Usage: $(basename "${0}") <resume|stop|continue|status>"
    echo ""
    echo "  resume    Wake a paused server immediately"
    echo "  stop      Force-disable auto-pause (server will not sleep until re-enabled)"
    echo "  continue  Re-enable auto-pause after 'stop'"
    echo "  status    Show current auto-pause state"
}

case "${1:-}" in
    resume)
        autopause_request_resume "manual (autopause resume)"
        es "> Resume requested."
        ;;
    stop)
        autopause_disable
        es "> Auto-pause force-disabled."
        ;;
    continue)
        autopause_enable
        es "> Auto-pause re-enabled."
        ;;
    status)
        if ! autopause_is_enabled; then
            e "Auto-pause: disabled (AUTO_PAUSE_ENABLED=false or missing prerequisites)"
        elif autopause_is_force_disabled; then
            e "Auto-pause: force-disabled (run 'autopause continue' to re-enable)"
        elif autopause_is_paused; then
            e "Auto-pause: server is currently PAUSED"
        else
            e "Auto-pause: active, watching for idle timeout (${AUTO_PAUSE_TIMEOUT:-180}s)"
        fi
        ;;
    *)
        print_usage
        exit 1
        ;;
esac
