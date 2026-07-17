#!/bin/bash
# Shared logging and command tracing with automatic size-based log rotation

# Setup base directories and parameters
LOG_DIR="${GAME_ROOT:-/palworld}/logs"
SCRIPT_NAME=$(basename "$0" .sh)
LOG_FILE="${LOG_FILE:-${LOG_DIR}/${SCRIPT_NAME}.log}"

# Default max log size to 10MB (10485760 bytes)
LOG_MAX_SIZE="${LOG_MAX_SIZE:-10485760}"
LOG_MAX_BACKUPS="${LOG_MAX_BACKUPS:-5}"

# Create directories
mkdir -p "$LOG_DIR" 2>/dev/null || true
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    chown steam:steam "$LOG_DIR" 2>/dev/null || true
fi

# Rotate log file if it exceeds the maximum size
if [[ -f "$LOG_FILE" ]]; then
    file_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    if [[ $file_size -ge $LOG_MAX_SIZE ]]; then
        # Shift backups (e.g. .4 -> .5, etc.)
        for ((i=LOG_MAX_BACKUPS-1; i>=1; i--)); do
            if [[ -f "${LOG_FILE}.${i}" ]]; then
                mv -f "${LOG_FILE}.${i}" "${LOG_FILE}.$((i+1))" 2>/dev/null || true
            fi
        done
        # Move current log to .1
        mv -f "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null || true
    fi
fi

# Ensure log file exists and has correct permissions
touch "$LOG_FILE" 2>/dev/null || true
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    chown steam:steam "$LOG_FILE" 2>/dev/null || true
fi

# Redirect stdout and stderr globally to log file while keeping console output
exec > >(tee -a "$LOG_FILE") 2>&1

# Define run_logged helper function to track command execution and mask secrets
run_logged() {
    local cmd_str="$*"
    local masked_cmd="$cmd_str"
    if [[ -n "${STEAM_PASSWORD:-}" ]]; then
        masked_cmd="${masked_cmd//"$STEAM_PASSWORD"/********}"
    fi
    if [[ -n "${ADMIN_PASSWORD:-}" ]]; then
        masked_cmd="${masked_cmd//"$ADMIN_PASSWORD"/********}"
    fi
    if [[ -n "${SERVER_PASSWORD:-}" ]]; then
        masked_cmd="${masked_cmd//"$SERVER_PASSWORD"/********}"
    fi

    # Use existing colored logging functions if defined, fallback otherwise
    if declare -F ei >/dev/null; then
        ei "[CMD] Running: $masked_cmd"
    else
        echo -e "\e[32mINFO:\e[0m [CMD] Running: $masked_cmd"
    fi

    local exit_code=0
    set +e
    "$@"
    exit_code=$?
    set -e

    if [[ $exit_code -eq 0 ]]; then
        if declare -F es >/dev/null; then
            es "[CMD] Success: $masked_cmd"
        else
            echo -e "\e[32mSUCCESS:\e[0m [CMD] Success: $masked_cmd"
        fi
        return 0
    else
        if declare -F ee >/dev/null; then
            ee "[CMD] Failed (Exit Code: $exit_code): $masked_cmd"
        else
            echo -e "\e[31mERROR:\e[0m [CMD] Failed (Exit Code: $exit_code): $masked_cmd"
        fi
        return $exit_code
    fi
}
