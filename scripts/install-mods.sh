#!/bin/bash
# shellcheck disable=SC1091

set -euo pipefail

# Print messages in color if colors.sh is available
if [[ -f "/includes/colors.sh" ]]; then
    source /includes/colors.sh
else
    # Fallback log functions
    ei() { echo -e "\e[32mINFO:\e[0m $*"; }
    ew() { echo -e "\e[33mWARN:\e[0m $*"; }
    ee() { echo -e "\e[31mERROR:\e[0m $*"; }
    es() { echo -e "\e[32mSUCCESS:\e[0m $*"; }
    e() { echo "$*"; }
fi

# Load restapi.sh if it exists (for check_is_server_empty, etc.)
if [[ -f "/includes/restapi.sh" ]]; then
    source /includes/restapi.sh
fi

GAME_ROOT="${GAME_ROOT:-/palworld}"
STEAMCMD_PATH="${STEAMCMD_PATH:-/home/steam/steamcmd}"

# 1. Mod ID sources: WORKSHOP_MOD_IDS (env) and /palworld/workshop-mods.txt
mod_ids=()

# Parse env var WORKSHOP_MOD_IDS (comma-separated list)
if [[ -n "${WORKSHOP_MOD_IDS:-}" ]]; then
    IFS=',' read -ra env_ids <<< "$WORKSHOP_MOD_IDS"
    for id in "${env_ids[@]}"; do
        trimmed=$(echo "$id" | xargs)
        if [[ -n "$trimmed" ]]; then
            mod_ids+=("$trimmed")
        fi
    done
fi

# Parse file-based IDs: /palworld/workshop-mods.txt
mods_txt="${GAME_ROOT}/workshop-mods.txt"
if [[ -f "$mods_txt" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip comments
        line="${line%%#*}"
        # Trim whitespace
        trimmed=$(echo "$line" | xargs)
        if [[ -n "$trimmed" ]]; then
            mod_ids+=("$trimmed")
        fi
    done < "$mods_txt"
fi

# Deduplicate IDs
unique_ids=()
declare -A seen
for id in "${mod_ids[@]}"; do
    if [[ -z "${seen[$id]:-}" ]]; then
        seen[$id]=1
        unique_ids+=("$id")
    fi
done

if [[ ${#unique_ids[@]} -eq 0 ]]; then
    ei "No Steam Workshop Mod IDs specified."
fi

# 2. Download mods via steamcmd
if [[ ${#unique_ids[@]} -gt 0 ]]; then
    ei "Preparing to download/update ${#unique_ids[@]} workshop mods..."
    steamcmd_args=("+login" "anonymous")
    for id in "${unique_ids[@]}"; do
        steamcmd_args+=("+workshop_download_item" "1623730" "$id")
    done
    steamcmd_args+=("+quit")

    # Run steamcmd, warn on failure but keep going
    ei "Running steamcmd..."
    if ! steamcmd "${steamcmd_args[@]}"; then
        ew "steamcmd reported errors during workshop download, will check downloaded directories..."
    fi
fi

# 3. Deploy mods into Mods/Workshop/
workshop_dir="${GAME_ROOT}/Mods/Workshop"
mkdir -p "$workshop_dir"

for id in "${unique_ids[@]}"; do
    # Try different potential SteamCMD download paths to ensure compatibility
    src_dir="/home/steam/Steam/steamapps/workshop/content/1623730/${id}"
    if [[ ! -d "$src_dir" ]]; then
        src_dir="/home/steam/.steam/steam/steamapps/workshop/content/1623730/${id}"
    fi
    if [[ ! -d "$src_dir" ]]; then
        src_dir="/home/steam/.local/share/Steam/steamapps/workshop/content/1623730/${id}"
    fi
    
    dest_dir="${workshop_dir}/${id}"
    
    if [[ -d "$src_dir" ]]; then
        ei "Deploying mod $id..."
        # Replace existing copy
        rm -rf "$dest_dir"
        mkdir -p "$dest_dir"
        cp -r "$src_dir"/. "$dest_dir"/
    else
        ew "Warning: Workshop mod $id was not found at $src_dir. Download might have failed."
    fi
done

# 4. Parse deployed mod's Info.json and rewrite ActiveModList in PalModSettings.ini
active_packages=()
for id in "${unique_ids[@]}"; do
    info_json="${workshop_dir}/${id}/Info.json"
    if [[ -f "$info_json" ]]; then
        pkg_name=$(jq -r '.PackageName // empty' "$info_json" 2>/dev/null || true)
        if [[ -n "$pkg_name" && "$pkg_name" != "null" ]]; then
            active_packages+=("$pkg_name")
        else
            ew "Warning: Mod ID $id Info.json is missing 'PackageName' or is malformed."
        fi
    else
        ew "Warning: Deployed mod ID $id Info.json not found."
    fi
done

ini_file="${GAME_ROOT}/Mods/PalModSettings.ini"
if [[ -f "$ini_file" ]]; then
    ei "Updating ${ini_file}..."
    new_ini=$(mktemp)
    in_active_list=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^\[ActiveModList\] ]]; then
            in_active_list=true
            continue
        elif [[ "$line" =~ ^\[ && "$in_active_list" == true ]]; then
            in_active_list=false
        fi
        
        if [[ "$in_active_list" == true ]]; then
            continue
        fi
        
        if [[ "$line" =~ ^bGlobalEnableMod= ]]; then
            echo "bGlobalEnableMod=true" >> "$new_ini"
        else
            echo "$line" >> "$new_ini"
        fi
    done < "$ini_file"
    
    # Ensure bGlobalEnableMod=true is set
    if ! grep -q "^bGlobalEnableMod=true" "$new_ini" 2>/dev/null; then
        if grep -q "^bGlobalEnableMod=" "$new_ini" 2>/dev/null; then
            sed -i 's/^bGlobalEnableMod=.*/bGlobalEnableMod=true/' "$new_ini"
        else
            if grep -q "\[Settings\]" "$new_ini" 2>/dev/null; then
                sed -i '/^\[Settings\]/a bGlobalEnableMod=true' "$new_ini"
            else
                echo -e "[Settings]\nbGlobalEnableMod=true\n$(cat "$new_ini")" > "$new_ini"
            fi
        fi
    fi

    # Append ActiveModList at the end
    echo "" >> "$new_ini"
    echo "[ActiveModList]" >> "$new_ini"
    for pkg in "${active_packages[@]}"; do
        echo "${pkg}=true" >> "$new_ini"
    done
    
    mv "$new_ini" "$ini_file"
    chmod 644 "$ini_file"
    chown steam:steam "$ini_file" 2>/dev/null || true
    es "Updated ActiveModList in PalModSettings.ini successfully."
else
    ei "PalModSettings.ini does not exist yet. Skipping ini update."
fi

# 5. Detect changes
state_file="${GAME_ROOT}/.workshop-mods-state.json"
current_state_json=$(jq -n '{}')

for id in "${unique_ids[@]}"; do
    info_json="${workshop_dir}/${id}/Info.json"
    if [[ -f "$info_json" ]]; then
        version=$(jq -r '.Version // "unknown"' "$info_json" 2>/dev/null || echo "unknown")
        current_state_json=$(echo "$current_state_json" | jq --arg id "$id" --arg ver "$version" '. + {($id): $ver}')
    else
        current_state_json=$(echo "$current_state_json" | jq --arg id "$id" '. + {($id): "missing"}')
    fi
done

changed=false
if [[ ! -f "$state_file" ]]; then
    changed=true
else
    old_state=$(jq -c . "$state_file" 2>/dev/null || echo "{}")
    new_state=$(echo "$current_state_json" | jq -c .)
    if [[ "$old_state" != "$new_state" ]]; then
        changed=true
    fi
fi

# Save the new state
echo "$current_state_json" | jq . > "$state_file"
chmod 644 "$state_file"
chown steam:steam "$state_file" 2>/dev/null || true

# 6. Check if server is running and handle restart
server_executable=$(basename "${GAME_BIN:-PalServer-Win64-Shipping-Cmd.exe}")
if pgrep -f "$server_executable" > /dev/null; then
    server_running=true
else
    server_running=false
fi

if [[ "$changed" == "true" ]]; then
    ei "Changes in workshop mods detected!"
    if [[ "$server_running" == "true" ]]; then
        if [[ "${RESTAPI_ENABLED:-false}" == "true" || "${RESTAPI_ENABLED:-false}" == "True" ]]; then
            ei "REST API is enabled. Preparing graceful shutdown..."
            countdown=${AUTO_UPDATE_COUNTDOWN:-${RESTART_COUNTDOWN:-15}}
            announce_enabled=${AUTO_UPDATE_ANNOUNCE_MESSAGES_ENABLED:-${RESTART_ANNOUNCE_MESSAGES_ENABLED:-true}}
            
            # Announce planned restart if webhook enabled
            if [[ "${WEBHOOK_ENABLED:-false}" == "true" ]]; then
                if [[ -f "/includes/webhook.sh" ]]; then
                    source /includes/webhook.sh
                    send_restart_planned_notification || true
                fi
            fi
            
            # Countdown
            for ((counter=$countdown; counter>=1; counter--)); do
                if check_is_server_empty; then
                    ew ">>> Server is empty, restarting now"
                    if [[ "${WEBHOOK_ENABLED:-false}" == "true" ]]; then
                        send_restart_now_notification 2>/dev/null || true
                    fi
                    break
                else
                    ew ">>> Server has players. Waiting..."
                fi
                if [[ "$announce_enabled" == "true" ]]; then
                    restapi_announce "MOD UPDATE: Server will restart in $counter minutes for workshop mod updates." || true
                fi
                sleep 60
            done
            
            # Save
            ei "Saving world..."
            if [[ "$announce_enabled" == "true" ]]; then
                restapi_announce "MOD UPDATE: Saving world before restart..." || true
            fi
            restapi_save || ew "Warning: Failed to save server state via REST API"
            sleep 5
            
            # Shutdown
            ei "Shutting down server..."
            restapi_shutdown 10 "Server restarting for mod updates..." || ew "Warning: Failed to shutdown server via REST API"
            
            if [[ "${WEBHOOK_ENABLED:-false}" == "true" ]]; then
                send_stop_notification 2>/dev/null || true
            fi
            
            exit 2
        else
            ew ">>> WARNING: Workshop mods have been updated/installed, but REST API is disabled."
            ew ">>> You must manually restart the Palworld server to apply these changes."
            exit 2
        fi
    else
        ei "Server is not running. Mods updated, no restart needed."
        exit 0
    fi
else
    ei "No changes in workshop mods detected."
    exit 0
fi
