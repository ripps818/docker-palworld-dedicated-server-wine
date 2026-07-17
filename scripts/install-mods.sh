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
WORKSHOP_MODS_DEBUG="${WORKSHOP_MODS_DEBUG:-false}"
INSTALL_UE4SS_EXPERIMENTAL="${INSTALL_UE4SS_EXPERIMENTAL:-false}"
UE4SS_EXPERIMENTAL_URL="${UE4SS_EXPERIMENTAL_URL:-https://github.com/Okaetsu/RE-UE4SS/releases/download/experimental-palworld/UE4SS-Palworld.zip}"

dbgi() {
    if [[ -n "${WORKSHOP_MODS_DEBUG:-}" ]] && [[ "${WORKSHOP_MODS_DEBUG,,}" == "true" ]]; then
        echo -e "\e[36mDEBUG:\e[0m $*"
    fi
}

# Locate the game's executable directory and the Mods base directory
bin_dir=$(dirname "${GAME_BIN:-/palworld/Pal/Binaries/Win64/PalServer-Win64-Shipping-Cmd.exe}")
if [[ "${INSTALL_UE4SS_EXPERIMENTAL,,}" == "true" ]] || [[ -d "${bin_dir}/ue4ss" ]]; then
    mods_base_dir="${bin_dir}/ue4ss/Mods"
else
    mods_base_dir="${bin_dir}/Mods"
fi

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

dbgi "Deduplicated Workshop Mod IDs to install/update: ${unique_ids[*]}"

if [[ ${#unique_ids[@]} -eq 0 ]]; then
    ei "No Steam Workshop Mod IDs specified."
fi

# 2. Download mods via steamcmd
if [[ ${#unique_ids[@]} -gt 0 ]]; then
    ei "Preparing to download/update ${#unique_ids[@]} workshop mods..."
    
    steamcmd_login=("anonymous")
    if [[ -n "${STEAM_USERNAME:-}" ]]; then
        if [[ -n "${STEAM_PASSWORD:-}" ]]; then
            steamcmd_login=("${STEAM_USERNAME}" "${STEAM_PASSWORD}")
        else
            steamcmd_login=("${STEAM_USERNAME}")
        fi
    fi

    steamcmd_args=("+login" "${steamcmd_login[@]}")
    for id in "${unique_ids[@]}"; do
        steamcmd_args+=("+workshop_download_item" "1623730" "$id")
    done
    steamcmd_args+=("+quit")

    # Print steamcmd command safely (mask password)
    if [[ -n "${STEAM_PASSWORD:-}" ]]; then
        dbgi "Running steamcmd with args: +login ${STEAM_USERNAME} ******** ${steamcmd_args[@]:3}"
    else
        dbgi "Running steamcmd with args: ${steamcmd_args[*]}"
    fi

    # Run steamcmd, warn on failure but keep going
    ei "Running steamcmd..."
    if ! steamcmd "${steamcmd_args[@]}"; then
        ew "steamcmd reported errors during workshop download, will check downloaded directories..."
    fi
fi

# Handle Okaetsu's UE4SS Experimental download/update/extraction
ue4ss_exp_local_zip="${GAME_ROOT}/Mods/ue4ss-experimental.zip"
ue4ss_exp_temp_zip="${GAME_ROOT}/Mods/ue4ss-experimental.zip.tmp"
ue4ss_exp_target_dir="${GAME_ROOT}/Mods/NativeMods/ue4ss-experimental"

if [[ "${INSTALL_UE4SS_EXPERIMENTAL,,}" == "true" ]]; then
    mkdir -p "${GAME_ROOT}/Mods"
    mkdir -p "${GAME_ROOT}/Mods/NativeMods"
    
    download_ok=false
    need_extract=false

    if [[ -f "$ue4ss_exp_local_zip" ]]; then
        ei "Checking for updates for UE4SS Experimental..."
        # Use -z to only download if the remote file is newer
        if curl -sSfL -z "$ue4ss_exp_local_zip" -o "$ue4ss_exp_temp_zip" "$UE4SS_EXPERIMENTAL_URL"; then
            download_ok=true
            if [[ -s "$ue4ss_exp_temp_zip" ]]; then
                ei "Newer version of UE4SS Experimental downloaded successfully."
                mv -f "$ue4ss_exp_temp_zip" "$ue4ss_exp_local_zip"
                need_extract=true
            else
                ei "UE4SS Experimental is already up to date."
                rm -f "$ue4ss_exp_temp_zip"
                if [[ ! -d "$ue4ss_exp_target_dir" ]]; then
                    need_extract=true
                fi
            fi
        else
            ew "Failed to check/download updates from $UE4SS_EXPERIMENTAL_URL. Falling back to cached version."
            # Fall back to cached version if it exists
            if [[ -f "$ue4ss_exp_local_zip" ]]; then
                download_ok=true
                if [[ ! -d "$ue4ss_exp_target_dir" ]]; then
                    need_extract=true
                fi
            else
                ee "No cached version of UE4SS Experimental found."
            fi
        fi
    else
        ei "Downloading UE4SS Experimental from $UE4SS_EXPERIMENTAL_URL..."
        if curl -sSfL -o "$ue4ss_exp_local_zip" "$UE4SS_EXPERIMENTAL_URL"; then
            download_ok=true
            need_extract=true
        else
            ee "Failed to download UE4SS Experimental."
        fi
    fi

    if [[ "$download_ok" == "true" && "$need_extract" == "true" ]]; then
        ei "Extracting UE4SS Experimental..."
        rm -rf "$ue4ss_exp_target_dir"
        mkdir -p "$ue4ss_exp_target_dir"
        if unzip -o "$ue4ss_exp_local_zip" -d "$ue4ss_exp_target_dir"; then
            es "Successfully extracted UE4SS Experimental to $ue4ss_exp_target_dir"
            chown -R steam:steam "$ue4ss_exp_target_dir" 2>/dev/null || true
        else
            ee "Failed to extract UE4SS Experimental zip file."
            rm -rf "$ue4ss_exp_target_dir"
        fi
    fi
else
    # If the flag is disabled, ensure the NativeMods target directory is removed
    # so it does not get deployed during the native mods phase.
    if [[ -d "$ue4ss_exp_target_dir" ]]; then
        ei "INSTALL_UE4SS_EXPERIMENTAL is disabled. Removing UE4SS Experimental native mod directory..."
        rm -rf "$ue4ss_exp_target_dir"
    fi
fi

# Purge legacy UE4SS files/directories if experimental UE4SS is activated to prevent conflicts
if [[ "${INSTALL_UE4SS_EXPERIMENTAL,,}" == "true" ]]; then
    ei "Purging legacy UE4SS files and Mods folder in Win64 directory to prevent conflicts..."
    for file in "UE4SS.dll" "UE4SS-settings.ini" "Vindsent.dll" "MemberVariableLayout.ini" "UE4SS.log"; do
        if [[ -f "${bin_dir}/${file}" ]]; then
            dbgi "Removing legacy UE4SS file: ${file}"
            rm -f "${bin_dir}/${file}"
        fi
    done
    if [[ -d "${bin_dir}/Mods" ]]; then
        dbgi "Removing legacy Mods folder"
        rm -rf "${bin_dir}/Mods"
    fi
fi

# 3. Clean up previously deployed .pak files and UE4SS DLLs/Configs to handle removed mods
state_file="${GAME_ROOT}/.workshop-mods-state.json"
if [[ -f "$state_file" ]]; then
    ei "Cleaning up previously deployed files from state..."
    
    # Determine old mods directory from state file to ensure proper cleanup
    old_mods_base_dir="${bin_dir}/Mods"
    if jq -e '.deployed_ue4ss_files[] | select(. == "ue4ss")' "$state_file" >/dev/null 2>&1; then
        old_mods_base_dir="${bin_dir}/ue4ss/Mods"
    fi

    # Read deployed_paks array and delete each file
    jq -r '.deployed_paks[]? // empty' "$state_file" 2>/dev/null | while read -r pak; do
        if [[ -n "$pak" ]]; then
            dbgi "Removing old deployed pak: ${pak}"
            rm -f "${GAME_ROOT}/Pal/Content/Paks/LogicMods/${pak}"
        fi
    done
    # Read deployed_ue4ss_files array and delete each file/directory
    jq -r '.deployed_ue4ss_files[]? // empty' "$state_file" 2>/dev/null | while read -r file; do
        if [[ -n "$file" ]]; then
            dbgi "Removing old deployed UE4SS file: ${file}"
            rm -rf "${bin_dir}/${file}"
        fi
    done
    # Read deployed_lua_mods array and delete each directory
    jq -r '.deployed_lua_mods[]? // empty' "$state_file" 2>/dev/null | while read -r lua_mod; do
        if [[ -n "$lua_mod" ]]; then
            dbgi "Removing old deployed Lua mod directory: ${lua_mod}"
            rm -rf "${old_mods_base_dir}/${lua_mod}"
        fi
    done
    # Read deployed_palschema_mods array and delete each directory
    jq -r '.deployed_palschema_mods[]? // empty' "$state_file" 2>/dev/null | while read -r palschema_mod; do
        if [[ -n "$palschema_mod" ]]; then
            dbgi "Removing old deployed PalSchema mod directory: ${palschema_mod}"
            rm -rf "${old_mods_base_dir}/PalSchema/mods/${palschema_mod}"
        fi
    done
fi

# Re-evaluate mods_base_dir in case UE4SS directories were cleaned up or changed
if [[ "${INSTALL_UE4SS_EXPERIMENTAL,,}" == "true" ]] || [[ -d "${bin_dir}/ue4ss" ]]; then
    mods_base_dir="${bin_dir}/ue4ss/Mods"
else
    mods_base_dir="${bin_dir}/Mods"
fi

# Arrays to keep track of currently deployed files for the new state
deployed_paks=()
deployed_ue4ss_files=()
deployed_lua_mods=()
deployed_palschema_mods=()

# Function to deploy a mod's files based on its auto-discovered folders/files (legacy fallback)
deploy_mod_auto_discover() {
    local dest_dir="$1"
    local pkg_name="${2:-}"
    if [[ -z "$pkg_name" ]]; then
        pkg_name=$(basename "$dest_dir")
    fi
    dbgi "Running deploy_mod_auto_discover on: $dest_dir"
    
    # 4a. Handle Logic Mods (.pak files)
    local logic_mods_dir="${GAME_ROOT}/Pal/Content/Paks/LogicMods"
    mkdir -p "$logic_mods_dir"
    while read -r pak_file; do
        if [[ -f "$pak_file" ]]; then
            local pak_name=$(basename "$pak_file")
            ei "  Found logic mod: $pak_name. Deploying to LogicMods..."
            cp -f "$pak_file" "$logic_mods_dir/"
            chown steam:steam "$logic_mods_dir/$pak_name" 2>/dev/null || true
            deployed_paks+=("$pak_name")
        fi
    done < <(find "$dest_dir" -type f -name "*.pak")

    # 4b. Handle UE4SS framework files (dwmapi.dll, UE4SS.dll, UE4SS-settings.ini)
    if [[ -d "${dest_dir}/ue4ss" ]]; then
        ei "  Found ue4ss folder. Deploying..."
        cp -r "${dest_dir}/ue4ss" "${bin_dir}/"
        chown -R steam:steam "${bin_dir}/ue4ss" 2>/dev/null || true
        deployed_ue4ss_files+=("ue4ss")
    fi

    if [[ -f "${dest_dir}/dwmapi.dll" ]]; then
        ei "  Found dwmapi.dll. Deploying..."
        cp -f "${dest_dir}/dwmapi.dll" "${bin_dir}/"
        chown steam:steam "${bin_dir}/dwmapi.dll" 2>/dev/null || true
        deployed_ue4ss_files+=("dwmapi.dll")
    elif [[ -f "${dest_dir}/UE4SS.dll" ]]; then
        ei "  Found UE4SS.dll. Deploying and copying to dwmapi.dll..."
        cp -f "${dest_dir}/UE4SS.dll" "${bin_dir}/dwmapi.dll"
        cp -f "${dest_dir}/UE4SS.dll" "${bin_dir}/UE4SS.dll"
        chown steam:steam "${bin_dir}/dwmapi.dll" "${bin_dir}/UE4SS.dll" 2>/dev/null || true
        deployed_ue4ss_files+=("dwmapi.dll" "UE4SS.dll")
    fi

    # Check for other dlls or settings
    for file in "UE4SS-settings.ini" "Vindsent.dll" "MemberVariableLayout.ini"; do
        if [[ -f "${dest_dir}/${file}" ]]; then
            ei "  Found UE4SS file: $file. Deploying..."
            cp -f "${dest_dir}/${file}" "${bin_dir}/"
            chown steam:steam "${bin_dir}/${file}" 2>/dev/null || true
            deployed_ue4ss_files+=("$file")
        fi
    done

    # If this is a UE4SS mod with a Mods folder, copy its contents to Mods directory
    if [[ -d "${dest_dir}/Mods" ]]; then
        ei "  Found UE4SS Mods folder. Deploying contents to ${mods_base_dir}..."
        cp -r "${dest_dir}/Mods"/. "${mods_base_dir}"/
        chown -R steam:steam "${mods_base_dir}" 2>/dev/null || true
        # Track deployed Lua mod directories or PalSchema mods for state cleanup
        for d in "${dest_dir}/Mods"/*; do
            if [[ -d "$d" ]]; then
                local mod_name=$(basename "$d")
                if [[ "$mod_name" == "PalSchema" && -d "$d/mods" ]]; then
                    # It's a PalSchema package containing sub-mods
                    for sub_d in "$d/mods"/*; do
                        if [[ -d "$sub_d" ]]; then
                            deployed_palschema_mods+=($(basename "$sub_d"))
                        fi
                    done
                else
                    # Standard Lua mod, or PalSchema framework itself
                    deployed_lua_mods+=("$mod_name")
                fi
            fi
        done
    fi

    # 4c. Handle PalSchema mods (either inside a 'PalSchema/mods' folder, a flat 'PalSchema' folder, or 'mods' folder)
    if [[ -d "${dest_dir}/PalSchema/mods" ]]; then
        ei "  Found PalSchema mods directory. Deploying..."
        mkdir -p "${mods_base_dir}/PalSchema/mods"
        cp -r "${dest_dir}/PalSchema/mods"/. "${mods_base_dir}/PalSchema/mods"/
        chown -R steam:steam "${mods_base_dir}/PalSchema/mods" 2>/dev/null || true
        for d in "${dest_dir}/PalSchema/mods"/*; do
            if [[ -d "$d" ]]; then
                deployed_palschema_mods+=($(basename "$d"))
            fi
        done
    elif [[ -d "${dest_dir}/PalSchema" ]]; then
        # Check if it is the PalSchema framework itself
        if [[ -f "${dest_dir}/PalSchema/scripts/main.lua" || -f "${dest_dir}/PalSchema/main.lua" ]]; then
            ei "  Found PalSchema framework. Deploying as Lua mod..."
            cp -r "${dest_dir}/PalSchema" "${mods_base_dir}/"
            chown -R steam:steam "${mods_base_dir}/PalSchema" 2>/dev/null || true
            deployed_lua_mods+=("PalSchema")
        else
            # Otherwise, treat the entire PalSchema folder as a single PalSchema mod under the package's name
            ei "  Found PalSchema mod folder. Deploying to PalSchema/mods/${pkg_name}..."
            local dest="${mods_base_dir}/PalSchema/mods/${pkg_name}"
            mkdir -p "$dest"
            cp -r "${dest_dir}/PalSchema"/. "$dest"/
            chown -R steam:steam "$dest" 2>/dev/null || true
            deployed_palschema_mods+=("$pkg_name")
        fi
    elif [[ -d "${dest_dir}/mods" ]]; then
        ei "  Found PalSchema mods directory (lowercase mods). Deploying..."
        mkdir -p "${mods_base_dir}/PalSchema/mods"
        cp -r "${dest_dir}/mods"/. "${mods_base_dir}/PalSchema/mods"/
        chown -R steam:steam "${mods_base_dir}/PalSchema/mods" 2>/dev/null || true
        for d in "${dest_dir}/mods"/*; do
            if [[ -d "$d" ]]; then
                deployed_palschema_mods+=($(basename "$d"))
            fi
        done
    fi

    # 4d. Handle flat PalSchema mods (contains blueprints, raw, translations, or items folder at root)
    local is_flat_palschema=false
    for dir in "blueprints" "raw" "translations" "items"; do
        if [[ -d "${dest_dir}/${dir}" ]]; then
            is_flat_palschema=true
            break
        fi
    done
    
    if [[ "$is_flat_palschema" == "true" ]]; then
        ei "  Found flat PalSchema mod. Deploying to PalSchema/mods/${pkg_name}..."
        local dest="${mods_base_dir}/PalSchema/mods/${pkg_name}"
        mkdir -p "$dest"
        cp -r "${dest_dir}"/. "$dest"/
        chown -R steam:steam "$dest" 2>/dev/null || true
        deployed_palschema_mods+=("$pkg_name")
    fi
}

# Function to deploy a mod's files using the official InstallRule schema from Info.json
deploy_mod_via_rules() {
    local dest_dir="$1"
    local pkg_name="$2"
    local info_json="${dest_dir}/Info.json"
    
    dbgi "Running deploy_mod_via_rules: dest_dir=$dest_dir, pkg_name=$pkg_name"
    ei "  Parsing InstallRule manifest..."
    
    # Heuristic: If there are any rules with IsServer == true, process only those.
    # Otherwise, process all rules (assuming the mod does not define IsServer but is generic).
    local rules_json
    if jq -e '.InstallRule[]? | select(.IsServer == true)' "$info_json" >/dev/null 2>&1; then
        rules_json=$(jq -c '.InstallRule[]? | select(.IsServer == true)' "$info_json" 2>/dev/null)
    else
        rules_json=$(jq -c '.InstallRule[]?' "$info_json" 2>/dev/null)
    fi
    
    dbgi "Parsed rules: $rules_json"
    
    while read -r rule; do
        if [[ -z "$rule" ]]; then
            continue
        fi
        
        local type=$(echo "$rule" | jq -r '.Type // empty')
        
        # Read the Targets array
        while read -r target; do
            # Trim leading "./" or "/" if present
            local clean_target="${target#./}"
            clean_target="${clean_target#/}"
            local target_path="${dest_dir}/${clean_target}"
            
            # If target_path is just "." or empty, it refers to the dest_dir itself
            if [[ "$clean_target" == "." || -z "$clean_target" ]]; then
                target_path="$dest_dir"
            fi
            
            dbgi "Processing rule: type=$type, target=$target, clean_target=$clean_target, target_path=$target_path"
            
            if [[ -e "$target_path" ]]; then
                if [[ "$type" == "Lua" ]]; then
                    local dest="${mods_base_dir}/${pkg_name}"
                    ei "    [Lua] Copying $target to $dest..."
                    mkdir -p "$dest"
                    if [[ -d "$target_path" ]]; then
                        cp -r "$target_path"/. "$dest"/
                    else
                        cp -f "$target_path" "$dest"/
                    fi
                    chown -R steam:steam "$dest" 2>/dev/null || true
                    deployed_lua_mods+=("$pkg_name")
                elif [[ "$type" == "Paks" ]]; then
                    local logic_mods_dir="${GAME_ROOT}/Pal/Content/Paks/LogicMods"
                    ei "    [Paks] Copying .pak files from $target to LogicMods..."
                    mkdir -p "$logic_mods_dir"
                    # Find and copy all .pak files in the target directory
                    while read -r pak_file; do
                        local pak_name=$(basename "$pak_file")
                        cp -f "$pak_file" "$logic_mods_dir/"
                        chown steam:steam "$logic_mods_dir/$pak_name" 2>/dev/null || true
                        deployed_paks+=("$pak_name")
                    done < <(find "$target_path" -type f -name "*.pak")
                elif [[ "$type" == "PalSchema" ]]; then
                    local dest="${mods_base_dir}/PalSchema/mods/${pkg_name}"
                    ei "    [PalSchema] Deploying files from $target to $dest..."
                    mkdir -p "$dest"
                    if [[ -d "$target_path" ]]; then
                        cp -r "$target_path"/. "$dest"/
                    else
                        cp -f "$target_path" "$dest"/
                    fi
                    chown -R steam:steam "$dest" 2>/dev/null || true
                    deployed_palschema_mods+=("$pkg_name")
                elif [[ "$type" == "UE4SS" ]]; then
                    ei "    [UE4SS] Deploying framework files from $target to $bin_dir..."
                    if [[ -d "$target_path" ]]; then
                        # Check for the modern UE4SS v3+ layout 'ue4ss' folder
                        if [[ -d "${target_path}/ue4ss" ]]; then
                            ei "    [UE4SS] Found ue4ss folder. Deploying..."
                            cp -r "${target_path}/ue4ss" "${bin_dir}/"
                            chown -R steam:steam "${bin_dir}/ue4ss" 2>/dev/null || true
                            deployed_ue4ss_files+=("ue4ss")
                        fi
                        # Copy dwmapi.dll, UE4SS.dll, UE4SS-settings.ini, etc.
                        if [[ -f "${target_path}/dwmapi.dll" ]]; then
                            cp -f "${target_path}/dwmapi.dll" "${bin_dir}/"
                            chown steam:steam "${bin_dir}/dwmapi.dll" 2>/dev/null || true
                            deployed_ue4ss_files+=("dwmapi.dll")
                        elif [[ -f "${target_path}/UE4SS.dll" ]]; then
                            cp -f "${target_path}/UE4SS.dll" "${bin_dir}/dwmapi.dll"
                            cp -f "${target_path}/UE4SS.dll" "${bin_dir}/UE4SS.dll"
                            chown steam:steam "${bin_dir}/dwmapi.dll" "${bin_dir}/UE4SS.dll" 2>/dev/null || true
                            deployed_ue4ss_files+=("dwmapi.dll" "UE4SS.dll")
                        fi
                        for file in "UE4SS-settings.ini" "Vindsent.dll" "MemberVariableLayout.ini"; do
                            if [[ -f "${target_path}/${file}" ]]; then
                                cp -f "${target_path}/${file}" "${bin_dir}/"
                                chown steam:steam "${bin_dir}/${file}" 2>/dev/null || true
                                deployed_ue4ss_files+=("$file")
                            fi
                        done
                        # Copy Mods directory if exists
                        if [[ -d "${target_path}/Mods" ]]; then
                            cp -r "${target_path}/Mods"/. "${mods_base_dir}"/
                            chown -R steam:steam "${mods_base_dir}" 2>/dev/null || true
                            # Track deployed Lua mod directories for state cleanup
                            for d in "${target_path}/Mods"/*; do
                                if [[ -d "$d" ]]; then
                                    deployed_lua_mods+=($(basename "$d"))
                                fi
                            done
                        fi
                    fi
                fi
            else
                ew "    Warning: Target path $target_path not found for type $type"
            fi
        done < <(echo "$rule" | jq -r '.Targets[]? // empty')
    done < <(echo "$rules_json")
}

# Main dispatcher function to deploy a mod folder
deploy_mod() {
    local src_dir="$1"
    local dest_dir="$2"
    local pkg_name="$3"
    
    dbgi "deploy_mod: src_dir=$src_dir, dest_dir=$dest_dir, pkg_name=$pkg_name"
    if [[ -d "$src_dir" ]]; then
        dbgi "  Clearing and recreating $dest_dir"
        # Replace existing copy of the raw mod
        rm -rf "$dest_dir"
        mkdir -p "$dest_dir"
        dbgi "  Copying files from $src_dir to $dest_dir"
        cp -r "$src_dir"/. "$dest_dir"/

        local info_json="${dest_dir}/Info.json"
        if [[ -f "$info_json" ]] && jq -e '.InstallRule' "$info_json" >/dev/null 2>&1; then
            dbgi "  Info.json has InstallRule. Deploying via rules..."
            deploy_mod_via_rules "$dest_dir" "$pkg_name"
        else
            dbgi "  No InstallRule found in Info.json. Deploying via auto-discover..."
            deploy_mod_auto_discover "$dest_dir" "$pkg_name"
        fi
    else
        dbgi "  Warning: src_dir $src_dir does not exist."
    fi
}

# 4. Deploy Workshop mods into Mods/Workshop/
workshop_dir="${mods_base_dir}/Workshop"
mkdir -p "$workshop_dir"

for id in "${unique_ids[@]}"; do
    dbgi "Processing Workshop Mod ID: $id"
    # Try different potential SteamCMD download paths to ensure compatibility
    src_dir="/home/steam/Steam/steamapps/workshop/content/1623730/${id}"
    dbgi "  Checking path: $src_dir"
    if [[ ! -d "$src_dir" ]]; then
        src_dir="/home/steam/.steam/steam/steamapps/workshop/content/1623730/${id}"
        dbgi "  Checking path: $src_dir"
    fi
    if [[ ! -d "$src_dir" ]]; then
        src_dir="/home/steam/.local/share/Steam/steamapps/workshop/content/1623730/${id}"
        dbgi "  Checking path: $src_dir"
    fi
    
    dest_dir="${workshop_dir}/${id}"
    dbgi "  Destination path: $dest_dir"
    
    if [[ -d "$src_dir" ]]; then
        pkg_name=$(jq -r '.PackageName // empty' "${src_dir}/Info.json" 2>/dev/null || true)
        if [[ -z "$pkg_name" || "$pkg_name" == "null" ]]; then
            pkg_name="$id"
        fi
        ei "Deploying Workshop mod $id ($pkg_name)..."
        deploy_mod "$src_dir" "$dest_dir" "$pkg_name"
    else
        ew "Warning: Workshop mod $id was not found at $src_dir. Download might have failed."
    fi
done

# Deploy native/manual mods from /palworld/Mods/NativeMods
native_mods_dir="${GAME_ROOT}/Mods/NativeMods"
mkdir -p "$native_mods_dir" 2>/dev/null || true
chown steam:steam "$native_mods_dir" 2>/dev/null || true

native_mod_names=()
if [[ -d "$native_mods_dir" ]]; then
    dbgi "Scanning Native mods directory: $native_mods_dir"
    for mod_path in "$native_mods_dir"/*; do
        if [[ -d "$mod_path" ]]; then
            mod_name=$(basename "$mod_path")
            dbgi "  Found Native mod: $mod_name at $mod_path"
            ei "Deploying Native mod $mod_name..."
            dest_dir="${mods_base_dir}/${mod_name}"
            pkg_name=$(jq -r '.PackageName // empty' "${mod_path}/Info.json" 2>/dev/null || true)
            if [[ -z "$pkg_name" || "$pkg_name" == "null" ]]; then
                pkg_name="$mod_name"
            fi
            deploy_mod "$mod_path" "$dest_dir" "$pkg_name"
            native_mod_names+=("$mod_name")
        fi
    done
fi

# 4c. Parse deployed mod's Info.json and rewrite ActiveModList in PalModSettings.ini
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

for mod_name in "${native_mod_names[@]}"; do
    info_json="${mods_base_dir}/${mod_name}/Info.json"
    if [[ -f "$info_json" ]]; then
        pkg_name=$(jq -r '.PackageName // empty' "$info_json" 2>/dev/null || true)
        if [[ -n "$pkg_name" && "$pkg_name" != "null" ]]; then
            active_packages+=("$pkg_name")
        else
            active_packages+=("$mod_name")
        fi
    else
        active_packages+=("$mod_name")
    fi
done

ini_file="${mods_base_dir}/PalModSettings.ini"
if [[ -f "$ini_file" ]]; then
    dbgi "Updating PalModSettings.ini. Active packages to write: ${active_packages[*]}"
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

# Update mods.txt in Mods folder to enable deployed Lua mods
mods_txt_file="${mods_base_dir}/mods.txt"
if [[ -f "$mods_txt_file" ]]; then
    dbgi "Updating mods.txt. Active packages: ${active_packages[*]}"
    new_mods_txt=$(mktemp)
    
    declare -A processed_custom_mods
    default_ue4ss_mods=("BPModLoaderMod" "CheatManagerEnablerMod" "ConsoleCommandsMod" "ConsoleEnablerMod" "BPML_GenericFunctions" "Keybinds" "CustomBus")
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Parse the mod name (trimming whitespace and colon)
        # e.g., "ConsoleEnablerMod : 0" -> "ConsoleEnablerMod"
        if [[ "$line" =~ ^[[:space:]]*([^[:space:]:]+)[[:space:]]*:[[:space:]]*(0|1) ]]; then
            m_name="${BASH_REMATCH[1]}"
            is_active=false
            for pkg in "${active_packages[@]}"; do
                if [[ "$pkg" == "$m_name" ]]; then
                    is_active=true
                    break
                fi
            done
            
            if [[ "$is_active" == true ]]; then
                echo "${m_name} : 1" >> "$new_mods_txt"
                processed_custom_mods["$m_name"]=1
            else
                # Check if this mod is a default UE4SS mod
                is_default=false
                for def_mod in "${default_ue4ss_mods[@]}"; do
                    if [[ "$def_mod" == "$m_name" ]]; then
                        is_default=true
                        break
                    fi
                done
                
                if [[ "$is_default" == true ]]; then
                    echo "$line" >> "$new_mods_txt"
                else
                    dbgi "Omit removed custom mod from mods.txt: ${m_name}"
                fi
            fi
        else
            echo "$line" >> "$new_mods_txt"
        fi
    done < "$mods_txt_file"
    
    # For any active packages that have a directory in mods_base_dir but weren't in mods.txt yet, append them
    for pkg in "${active_packages[@]}"; do
        if [[ -d "${mods_base_dir}/${pkg}" ]] && [[ -z "${processed_custom_mods[$pkg]:-}" ]]; then
            dbgi "Appending new mod to mods.txt: ${pkg} : 1"
            echo "${pkg} : 1" >> "$new_mods_txt"
        fi
    done
    
    mv "$new_mods_txt" "$mods_txt_file"
    chmod 644 "$mods_txt_file"
    chown steam:steam "$mods_txt_file" 2>/dev/null || true
    es "Updated mods.txt successfully."
else
    ei "mods.txt does not exist yet. Skipping mods.txt update."
fi

# 5. Detect changes
state_file="${GAME_ROOT}/.workshop-mods-state.json"
versions_json=$(jq -n '{}')

for id in "${unique_ids[@]}"; do
    info_json="${workshop_dir}/${id}/Info.json"
    if [[ -f "$info_json" ]]; then
        version=$(jq -r '.Version // "unknown"' "$info_json" 2>/dev/null || echo "unknown")
        versions_json=$(echo "$versions_json" | jq --arg id "$id" --arg ver "$version" '. + {($id): $ver}')
    else
        versions_json=$(echo "$versions_json" | jq --arg id "$id" '. + {($id): "missing"}')
    fi
done

for mod_name in "${native_mod_names[@]}"; do
    info_json="${mods_base_dir}/${mod_name}/Info.json"
    if [[ -f "$info_json" ]]; then
        version=$(jq -r '.Version // "unknown"' "$info_json" 2>/dev/null || echo "unknown")
        versions_json=$(echo "$versions_json" | jq --arg id "native_${mod_name}" --arg ver "$version" '. + {($id): $ver}')
    else
        versions_json=$(echo "$versions_json" | jq --arg id "native_${mod_name}" '. + {($id): "exists"}')
    fi
done

# Convert arrays to JSON arrays safely using jq
paks_json=$(jq -n '[]')
for pak in "${deployed_paks[@]}"; do
    paks_json=$(echo "$paks_json" | jq --arg pak "$pak" '. += [$pak]')
done

ue4ss_json=$(jq -n '[]')
for file in "${deployed_ue4ss_files[@]}"; do
    ue4ss_json=$(echo "$ue4ss_json" | jq --arg file "$file" '. += [$file]')
done

lua_mods_json=$(jq -n '[]')
for lmod in "${deployed_lua_mods[@]}"; do
    lua_mods_json=$(echo "$lua_mods_json" | jq --arg lmod "$lmod" '. += [$lmod]')
done

palschema_mods_json=$(jq -n '[]')
for pmod in "${deployed_palschema_mods[@]}"; do
    palschema_mods_json=$(echo "$palschema_mods_json" | jq --arg pmod "$pmod" '. += [$pmod]')
done

current_state_json=$(jq -n \
    --argjson versions "$versions_json" \
    --argjson paks "$paks_json" \
    --argjson ue4ss "$ue4ss_json" \
    --argjson lmods "$lua_mods_json" \
    --argjson psmods "$palschema_mods_json" \
    '{versions: $versions, deployed_paks: $paks, deployed_ue4ss_files: $ue4ss, deployed_lua_mods: $lmods, deployed_palschema_mods: $psmods}')

changed=false
if [[ ! -f "$state_file" ]]; then
    dbgi "State file does not exist. Triggering change..."
    changed=true
else
    old_state=$(jq -c . "$state_file" 2>/dev/null || echo "{}")
    new_state=$(echo "$current_state_json" | jq -c .)
    dbgi "Old state: $old_state"
    dbgi "New state: $new_state"
    if [[ "$old_state" != "$new_state" ]]; then
        dbgi "State difference detected!"
        changed=true
    fi
fi

# Save the new state
dbgi "Saving current state: $current_state_json"
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
