# shellcheck disable=SC2148
# Utility and helper functions for string sanitization, path formatting, and cross-platform compatibility.

# trim - Sanitizes string inputs by stripping carriage returns (\r) and trimming leading/trailing whitespace.
#
# WHY THIS IS NEEDED:
# When running inside Docker containers with host volume mounts (especially on Windows via VMM,
# Hyper-V, or WSL), text files (such as workshop-mods.txt, config INIs, or environment files)
# edited on Windows host machines default to CRLF (\r\n) line endings. In Bash, the trailing
# carriage return (\r) remains attached to parsed strings (e.g. "3761671501\r"), corrupting
# mod ID array lookups, file path resolution, PID parsing, and string comparisons.
#
# USAGE:
#   As an argument:  trimmed_val=$(trim "$raw_val")
#   Via stdin:       trimmed_val=$(echo "$raw_val" | trim)
#   From a file:     trimmed_val=$(trim < file.txt)
function trim() {
    local input
    if [[ $# -gt 0 ]]; then
        input="$*"
    else
        input="$(cat)"
    fi
    printf '%s\n' "$input" | tr -d '\r' | xargs
}
