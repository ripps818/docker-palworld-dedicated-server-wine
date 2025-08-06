# shellcheck disable=SC2148,SC1091

source /includes/colors.sh

current_setting=1
settings_amount=89

function setup_engine_ini() {
    ei ">>> Setting up Engine.ini ..."
    if [ ! -d "${GAME_CONFIG_PATH}" ]; then
        mkdir -p "${GAME_CONFIG_PATH}/"
    fi
    echo "[/Script/OnlineSubsystemUtils.IpNetDriver]" > "${GAME_ENGINE_FILE}"
    echo "NetServerMaxTickRate=${NETSERVERMAXTICKRATE}" >> "${GAME_ENGINE_FILE}"
    es ">>> Finished setting up Engine.ini!"
}

function e_with_counter() {
    local padded_number
    padded_number=$(printf "%02d" $current_setting)
    # shellcheck disable=SC2145
    e "> ($padded_number/$settings_amount) Setting $@"
    current_setting=$((current_setting + 1))
}

function setup_palworld_settings_ini() {
    ei ">>> Setting up PalWorldSettings.ini ..."
    if [ ! -d "${GAME_CONFIG_PATH}" ]; then
        mkdir -p "${GAME_CONFIG_PATH}/"
    fi
    # Copy default-config, which comes with SteamCMD to gameserver save location
    ew "> Copying PalWorldSettings.ini.template to ${GAME_SETTINGS_FILE}"
    envsubst < "${PALWORLD_TEMPLATE_FILE}" > "${GAME_SETTINGS_FILE}"
    es ">>> Finished setting up PalWorldSettings.ini"
}

function setup_rcon_yaml () {
    if [[ -n ${RCON_ENABLED+x} ]] && [ "$RCON_ENABLED" == "true" ] ; then
        ei ">>> RCON is enabled - Setting up rcon.yaml ..."
        # Ensure the directory exists and has proper permissions
        if [ ! -d "$(dirname "${RCON_CONFIG_FILE}")" ]; then
            mkdir -p "$(dirname "${RCON_CONFIG_FILE}")"
            chown steam:steam "$(dirname "${RCON_CONFIG_FILE}")"
        fi
        ew "> Copying rcon.yaml.template to ${RCON_CONFIG_FILE}"
        envsubst < "/rcon.yaml.template" > "${RCON_CONFIG_FILE}"
        chown steam:steam "${RCON_CONFIG_FILE}"
        es ">>> Finished setting up 'rcon.yaml' config file"
    else
        ei ">>> RCON is disabled, skipping 'rcon.yaml' config file!"
    fi
}

function setup_configs() {
    if [[ -n ${SERVER_SETTINGS_MODE} ]] && [[ ${SERVER_SETTINGS_MODE} == "auto" ]]; then
        ew ">>> SERVER_SETTINGS_MODE is set to '${SERVER_SETTINGS_MODE}', using environment variables to configure the server"
        setup_engine_ini
        setup_palworld_settings_ini
        setup_rcon_yaml
    elif [[ -n ${SERVER_SETTINGS_MODE} ]] && [[ ${SERVER_SETTINGS_MODE} == "rcononly" ]]; then
        ew ">>> SERVER_SETTINGS_MODE is set to '${SERVER_SETTINGS_MODE}', using environment variables to ONLY configure RCON!"
        ew ">>> ALL SETTINGS excluding setup of rcon.yaml has to be done manually by the user!"
        setup_rcon_yaml
    else
        ew ">>> SERVER_SETTINGS_MODE is set to '${SERVER_SETTINGS_MODE}', NOT using environment variables to configure the server!"
        ew ">>> ALL SETTINGS including setup of rcon.yaml has to be done manually by the user!"
    fi
}
