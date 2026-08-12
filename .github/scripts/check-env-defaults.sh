#!/bin/bash
# Keeps docs/ENV_VARS.md, Dockerfile, and default.env from drifting apart. Run from the repo root.
set -euo pipefail

# Internal architecture constants, never meant to be user-tunable - excluded from the docs check.
internal_vars=(
    DEBIAN_FRONTEND DISPLAY
    GAME_BIN GAME_CONFIG_PATH GAME_ENGINE_FILE GAME_PATH GAME_ROOT
    GAME_SAVE_PATH GAME_SETTINGS_FILE PALWORLD_TEMPLATE_FILE STEAMCMD_PATH
    STEAMCMD_URL SUPERCRONIC SUPERCRONIC_SHA1SUM SUPERCRONIC_URL
    WINE_BIN WINEARCH WINEDEBUG WINEDLLOVERRIDES WINEPREFIX WINETRICK_BIN
)

documented=$(grep -E '^\| *`?[A-Z][A-Z0-9_]+(`| |\|)' docs/ENV_VARS.md | sed -E 's/^\| *`?([A-Z0-9_]+)`?.*/\1/' | sort -u)
in_dockerfile=$(grep -oP '^\s*(?:ENV\s+)?[A-Z][A-Z0-9_]*(?==)' Dockerfile | sed -E 's/^\s*(ENV\s+)?//' | sort -u)

missing=0

echo "--- Checking every documented var has a real default ---"
while IFS= read -r var; do
    [[ -z "$var" ]] && continue
    in_dockerfile_default=0
    in_default_env=0
    grep -qE "^\s*${var}=" Dockerfile && in_dockerfile_default=1
    grep -qE "^${var}=" default.env && in_default_env=1

    if [[ $in_dockerfile_default -eq 0 || $in_default_env -eq 0 ]]; then
        missing_from=""
        [[ $in_dockerfile_default -eq 0 ]] && missing_from+=" Dockerfile"
        [[ $in_default_env -eq 0 ]] && missing_from+=" default.env"
        echo "::error::${var} is documented in docs/ENV_VARS.md but missing a default in:${missing_from}"
        missing=1
    fi
done <<< "$documented"

echo "--- Checking every Dockerfile var (excluding internal ones) is documented ---"
while IFS= read -r var; do
    [[ -z "$var" ]] && continue
    printf '%s\n' "${internal_vars[@]}" | grep -qxF "$var" && continue
    if ! printf '%s\n' "$documented" | grep -qxF "$var"; then
        echo "::error::${var} has a default in Dockerfile but is missing from docs/ENV_VARS.md"
        missing=1
    fi
done <<< "$in_dockerfile"

if [[ $missing -eq 1 ]]; then
    echo ""
    echo "docs/ENV_VARS.md, Dockerfile, and default.env have drifted out of sync."
    echo "A documented var with no real default can fail silently, or worse."
    echo ""
    echo "If a var is genuinely internal (not meant to be user-tunable), add it to"
    echo "the internal_vars list in this script instead of documenting it."
    exit 1
fi

echo "docs/ENV_VARS.md, Dockerfile, and default.env are in sync."
