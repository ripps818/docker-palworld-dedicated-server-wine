# shellcheck disable=SC2148,SC1091

source /includes/colors.sh

current_setting=1
settings_amount=108

function setup_engine_ini() {
    pattern1="OnlineSubsystemUtils.IpNetDriver"
    pattern2="^NetServerMaxTickRate=[0-9]*"
    ei ">>> Setting up Engine.ini ..."
    e "> Checking if config already exists..."
    if [ ! -f "${GAME_ENGINE_FILE}" ]; then
        ew "> No config found, generating one!"
        if [ ! -d "${GAME_CONFIG_PATH}" ]; then
            mkdir -p "${GAME_CONFIG_PATH}/"
        fi
        # Create empty Engine.ini file
        echo "" > "${GAME_ENGINE_FILE}"
    else
        e "> Found existing config!"
    fi
    if grep -qE "${pattern1}" "${GAME_ENGINE_FILE}" 2>/dev/null; then
        e "> Found [/Script/OnlineSubsystemUtils.IpNetDriver] section"
    else
        ew "> Found no [/Script/OnlineSubsystemUtils.IpNetDriver], adding it"
        echo -e "[/Script/OnlineSubsystemUtils.IpNetDriver]" >> "${GAME_ENGINE_FILE}"
    fi
    if grep -qE "${pattern2}" "${GAME_ENGINE_FILE}" 2>/dev/null; then
        e "> Found NetServerMaxTickRate parameter, changing it to '${NETSERVERMAXTICKRATE}'"
        sed -E -i "s/${pattern2}/NetServerMaxTickRate=${NETSERVERMAXTICKRATE}/" "${GAME_ENGINE_FILE}"
    else
        ew "> Found no NetServerMaxTickRate parameter, adding it with value '${NETSERVERMAXTICKRATE}'"
        echo "NetServerMaxTickRate=${NETSERVERMAXTICKRATE}" >> "${GAME_ENGINE_FILE}"
    fi
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
        mkdir -p "${GAME_CONFIG_PATH}/" || {
            ee "Failed to create directory ${GAME_CONFIG_PATH}"
            return 1
        }
    fi

    # if SERVER_NAME contains ###RANDOM###, replace it now
    if [[ "${SERVER_NAME:-}" == *"###RANDOM###"* ]]; then
        # generate a 6-char alphanumeric token
        rand="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 6)"
        export SERVER_NAME="${SERVER_NAME//###RANDOM###/${rand}}"
    fi

    # Copy default-config, which comes with SteamCMD to gameserver save location
    ew "> Copying PalWorldSettings.ini.template to ${GAME_SETTINGS_FILE}"
    ENVSUBST_SELECTORS='$SERVER_NAME $SERVER_DESCRIPTION $ADMIN_PASSWORD $SERVER_PASSWORD $PUBLIC_IP $PUBLIC_PORT $MAX_PLAYERS $COOP_PLAYER_MAX_NUM $ALLOW_CLIENT_MOD $RCON_ENABLED $RCON_PORT $RESTAPI_ENABLED $RESTAPI_PORT $REGION $USEAUTH $BAN_LIST_URL $SHOW_PLAYER_LIST $CHAT_POST_LIMIT_PER_MINUTE $CROSSPLAY_PLATFORMS $SHOW_JOIN_LEFT_MESSAGE
        $DIFFICULTY $DAYTIME_SPEEDRATE $NIGHTTIME_SPEEDRATE $EXP_RATE $PAL_CAPTURE_RATE $PAL_SPAWN_NUM_RATE $PAL_EGG_DEFAULT_HATCHING_TIME $WORK_SPEED_RATE $HARDCORE $PAL_LOST $CHARACTER_RECREATE_IN_HARDCORE $ENABLE_AIM_ASSIST_PAD $ENABLE_AIM_ASSIST_KEYBOARD
        $IS_PVP $ENABLE_PLAYER_TO_PLAYER_DAMAGE $ENABLE_FRIENDLY_FIRE $DEATH_PENALTY $ENABLE_INVADER_ENEMY $ACTIVE_UNKO $PAL_DAMAGE_RATE_ATTACK $PAL_DAMAGE_RATE_DEFENSE $PLAYER_DAMAGE_RATE_ATTACK $PLAYER_DAMAGE_RATE_DEFENSE $ENABLE_DEFENSE_OTHER_GUILD_PLAYER $DISPLAY_PVP_ITEM_NUM_ON_WORLD_MAP_BASE_CAMP $DISPLAY_PVP_ITEM_NUM_ON_WORLD_MAP_PLAYER $ADDITIONAL_DROP_ITEM_WHEN_PLAYER_KILLING_IN_PVP_MODE $ADDITIONAL_DROP_ITEM_NUM_WHEN_PLAYER_KILLING_IN_PVP_MODE $ENABLE_ADDITIONAL_DROP_ITEM_WHEN_PLAYER_KILLING_IN_PVP_MODE $ENABLE_PREDATOR_BOSS_PAL
        $PLAYER_STOMACH_DECREASE_RATE $PLAYER_STAMINA_DECREACE_RATE $PLAYER_AUTO_HP_REGENE_RATE $PLAYER_AUTO_HP_REGENE_RATE_IN_SLEEP $PAL_STOMACH_DECREACE_RATE $PAL_STAMINA_DECREACE_RATE $PAL_AUTO_HP_REGENE_RATE $PAL_AUTO_HP_REGENE_RATE_IN_SLEEP $EXIST_PLAYER_AFTER_LOGOUT $ENABLE_NON_LOGIN_PENALTY $ALLOW_ENHANCE_STAT_HEALTH $ALLOW_ENHANCE_STAT_ATTACK $ALLOW_ENHANCE_STAT_STAMINA $ALLOW_ENHANCE_STAT_WEIGHT $ALLOW_ENHANCE_STAT_WORK_SPEED
        $BASE_CAMP_MAX_NUM $BASE_CAMP_WORKER_MAXNUM $BASE_CAMP_MAX_NUM_IN_GUILD $GUILD_PLAYER_MAX_NUM $AUTO_RESET_GUILD_NO_ONLINE_PLAYERS $AUTO_RESET_GUILD_TIME_NO_ONLINE_PLAYERS $GUILD_REJOIN_COOLDOWN_MINUTES $BUILD_OBJECT_HP_RATE $BUILD_OBJECT_DAMAGE_RATE $BUILD_OBJECT_DETERIORATION_DAMAGE_RATE $MAX_BUILDING_LIMIT_NUM $BUILD_AREA_LIMIT $INVISBIBLE_OTHER_GUILD_BASE_CAMP_AREA_FX
        $COLLECTION_DROP_RATE $COLLECTION_OBJECT_HP_RATE $COLLECTION_OBJECT_RESPAWN_SPEED_RATE $ENEMY_DROP_ITEM_RATE $DROP_ITEM_MAX_NUM $DROP_ITEM_MAX_NUM_UNKO $DROP_ITEM_ALIVE_MAX_HOURS $ITEM_WEIGHT_RATE $EQUIPMENT_DURABILITY_DAMAGE_RATE $ITEM_CONTAINER_FORCE_MARK_DIRTY_INTERVAL $ITEM_CORRUPTION_MULTIPLIER
        $ENABLE_FAST_TRAVEL $ENABLE_FAST_TRAVEL_ONLY_BASE_CAMP $IS_START_LOCATION_SELECT_BY_MAP $CAN_PICKUP_OTHER_GUILD_DEATH_PENALTY_DROP $SUPPLY_DROP_SPAN $SERVER_REPLICATE_PAWN_CULL_DISTANCE $ALLOW_GLOBAL_PALBOX_EXPORT $ALLOW_GLOBAL_PALBOX_IMPORT $ENABLE_WORLD_BACKUP $AUTO_SAVE_SPAN $LOG_FORMAT_TYPE $BLOCK_RESPAWN_TIME $RESPAWN_PENALTY_DURATION_THRESHOLD $RESPAWN_PENALTY_TIME_SCALE
        $RANDOMIZER_TYPE $RANDOMIZER_SEED $IS_RANDOMIZER_PAL_LEVEL_RANDOM
        $IS_MULTIPLAY $DENY_TECHNOLOGY_LIST'
    

    if ! envsubst "$ENVSUBST_SELECTORS" < "${PALWORLD_TEMPLATE_FILE}" > "${GAME_SETTINGS_FILE}"; then
        ee "Failed to generate ${GAME_SETTINGS_FILE}"
        return 1
    fi
    es ">>> Finished setting up PalWorldSettings.ini"
}

function setup_rcon_yaml () {
    if [[ -n ${RCON_ENABLED+x} ]] && [[ "${RCON_ENABLED,,}" == "true" ]] ; then
        ei ">>> RCON is enabled - Setting up rcon.yaml ..."
        if [[ -n ${RCON_PORT+x} ]] && [[ -n ${ADMIN_PASSWORD+x} ]]; then
            TEMP_FILE=$(mktemp)
            if envsubst '$RCON_PORT $ADMIN_PASSWORD' < "$RCON_CONFIG_FILE" > "$TEMP_FILE"; then
                mv "$TEMP_FILE" "$RCON_CONFIG_FILE"
            else
                ee "Failed to process rcon.yaml"
                rm -f "$TEMP_FILE"
                return 1
            fi
        else
            ee "> RCON_PORT and/or ADMIN_PASSWORD are not set; please set both for RCON to work!"
        fi
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
