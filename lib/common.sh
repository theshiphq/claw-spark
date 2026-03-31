#!/usr/bin/env bash
# lib/common.sh — Shared utilities sourced by all clawspark scripts.
# Provides logging, prompts, color constants, spinner, and global paths.
set -euo pipefail

# ── Global paths ────────────────────────────────────────────────────────────
CLAWSPARK_DIR="${HOME}/.clawspark"
CLAWSPARK_LOG="${CLAWSPARK_DIR}/install.log"
CLAWSPARK_DEFAULTS="${CLAWSPARK_DEFAULTS:-false}"

# ── Color constants ─────────────────────────────────────────────────────────
if [[ -t 1 ]] && command -v tput &>/dev/null && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    CYAN=$(tput setaf 6)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[0;33m'
    BLUE=$'\033[0;34m'
    CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'
    RESET=$'\033[0m'
fi

# ── Helpers (Bash 3.2 compatible) ───────────────────────────────────────────
to_lower() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

# ── Logging ─────────────────────────────────────────────────────────────────
_ts() { date '+%H:%M:%S'; }

log_info() {
    printf '%s[%s]%s %s\n' "${BLUE}" "$(_ts)" "${RESET}" "$*"
    _log_to_file "INFO" "$*"
}

log_warn() {
    printf '%s[%s] WARNING:%s %s\n' "${YELLOW}" "$(_ts)" "${RESET}" "$*" >&2
    _log_to_file "WARN" "$*"
}

log_error() {
    printf '%s[%s] ERROR:%s %s\n' "${RED}" "$(_ts)" "${RESET}" "$*" >&2
    _log_to_file "ERROR" "$*"
}

log_success() {
    printf '%s[%s] OK:%s %s\n' "${GREEN}" "$(_ts)" "${RESET}" "$*"
    _log_to_file "OK" "$*"
}

_log_to_file() {
    local level="$1"; shift
    if [[ -d "${CLAWSPARK_DIR}" ]]; then
        printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${level}" "$*" \
            >> "${CLAWSPARK_LOG}" 2>/dev/null || true
    fi
}

# ── Prompt helpers ──────────────────────────────────────────────────────────

# prompt_choice QUESTION OPTIONS_ARRAY DEFAULT_INDEX
#   Displays numbered options and returns the selected value.
#   If CLAWSPARK_DEFAULTS=true, returns the default without prompting.
#
# Usage:
#   options=("Option A" "Option B" "Option C")
#   result=$(prompt_choice "Pick one:" options 0)
prompt_choice() {
    local question="$1"
    local options_name="$2"       # array name (Bash 3.2 compatible: no nameref)
    local default_idx="${3:-0}"
    local count
    eval "count=\${#${options_name}[@]}"

    # If running in defaults mode, return default immediately
    if [[ "${CLAWSPARK_DEFAULTS}" == "true" ]]; then
        eval "printf '%s' \"\${${options_name}[$default_idx]}\""
        return 0
    fi

    # Print menu to /dev/tty so it's visible even inside $(...) capture
    printf '\n%s%s%s\n' "${BOLD}" "${question}" "${RESET}" >/dev/tty
    local i
    for i in $(seq 0 $(( count - 1 ))); do
        local marker=""
        if [[ "$i" -eq "$default_idx" ]]; then
            marker=" ${CYAN}(default)${RESET}"
        fi
        local opt
        eval "opt=\${${options_name}[$i]}"
        printf '  %s%d)%s %s%s\n' "${GREEN}" $(( i + 1 )) "${RESET}" "${opt}" "${marker}" >/dev/tty
    done

    local selection
    while true; do
        printf '%s> %s' "${BOLD}" "${RESET}" >/dev/tty
        read -r selection </dev/tty || selection=""
        # Empty input → default
        if [[ -z "${selection}" ]]; then
            eval "printf '%s' \"\${${options_name}[$default_idx]}\""
            return 0
        fi
        # Validate numeric input
        if [[ "${selection}" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= count )); then
            eval "printf '%s' \"\${${options_name}[$(( selection - 1 ))]}\""
            return 0
        fi
        printf '  %sPlease enter a number between 1 and %d%s\n' "${YELLOW}" "${count}" "${RESET}" >/dev/tty
    done
}

# prompt_yn QUESTION DEFAULT(y/n)
#   Returns 0 for yes, 1 for no.
prompt_yn() {
    local question="$1"
    local default="${2:-y}"

    if [[ "${CLAWSPARK_DEFAULTS}" == "true" ]]; then
        [[ "${default}" == "y" ]] && return 0 || return 1
    fi

    local hint
    if [[ "${default}" == "y" ]]; then hint="[Y/n]"; else hint="[y/N]"; fi

    printf '\n%s%s %s%s ' "${BOLD}" "${question}" "${hint}" "${RESET}" >/dev/tty
    local answer
    read -r answer </dev/tty || answer=""
    answer=$(to_lower "${answer}")

    if [[ -z "${answer}" ]]; then
        [[ "${default}" == "y" ]] && return 0 || return 1
    fi
    [[ "${answer}" =~ ^y(es)?$ ]] && return 0 || return 1
}

# ── check_command ───────────────────────────────────────────────────────────
# Returns 0 if the command exists on PATH, 1 otherwise.
check_command() {
    command -v "$1" &>/dev/null
}

# ── Spinner ─────────────────────────────────────────────────────────────────
# spinner PID "message"
#   Shows a spinner while a background process runs.
#   Usage:
#     long_running_command &
#     spinner $! "Installing widgets..."
spinner() {
    local pid="$1"
    local msg="${2:-Working...}"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local frame_count=${#frames[@]}
    local i=0

    # Only show spinner if stdout is a terminal
    if [[ ! -t 1 ]]; then
        wait "${pid}" 2>/dev/null || true
        return 0
    fi

    printf '  '
    while kill -0 "${pid}" 2>/dev/null; do
        printf '\r  %s%s%s %s' "${CYAN}" "${frames[i % frame_count]}" "${RESET}" "${msg}"
        i=$(( i + 1 ))
        sleep 0.08
    done

    # Capture exit status of the background process
    wait "${pid}" 2>/dev/null
    local exit_code=$?

    if [[ ${exit_code} -eq 0 ]]; then
        printf '\r  %s✓%s %s\n' "${GREEN}" "${RESET}" "${msg}"
    else
        printf '\r  %s✗%s %s\n' "${RED}" "${RESET}" "${msg}"
    fi
    # Always return 0 so set -e does not abort the installer.
    # Callers should validate success themselves (e.g. check_command).
    return 0
}

# ── Horizontal rule ────────────────────────────────────────────────────────
hr() {
    local cols
    cols=$(tput cols 2>/dev/null || echo 60)
    printf '%s%*s%s\n' "${BLUE}" "${cols}" '' "${RESET}" | tr ' ' '─'
}

# ── Box drawing ─────────────────────────────────────────────────────────────
# print_box "line1" "line2" ...
#   Draws a bordered box around the given lines.
print_box() {
    local lines=("$@")
    local max_len=0
    local line

    for line in "${lines[@]}"; do
        # Strip ANSI codes when measuring length
        local stripped
        stripped=$(printf '%s' "${line}" | sed 's/\x1b\[[0-9;]*m//g')
        (( ${#stripped} > max_len )) && max_len=${#stripped}
    done

    local pad=$(( max_len + 2 ))
    printf '%s┌%s┐%s\n' "${BLUE}" "$(printf '─%.0s' $(seq 1 "${pad}"))" "${RESET}"
    for line in "${lines[@]}"; do
        local stripped
        stripped=$(printf '%s' "${line}" | sed 's/\x1b\[[0-9;]*m//g')
        local spaces=$(( max_len - ${#stripped} ))
        printf '%s│%s %s%*s %s│%s\n' "${BLUE}" "${RESET}" "${line}" "${spaces}" '' "${BLUE}" "${RESET}"
    done
    printf '%s└%s┘%s\n' "${BLUE}" "$(printf '─%.0s' $(seq 1 "${pad}"))" "${RESET}"
}

# ── Skills YAML parser ────────────────────────────────────────────────────
# _parse_enabled_skills FILE
#   Prints one skill slug per line from the "enabled:" section.
#   Handles both "- name: slug" and "- slug" formats.
_parse_enabled_skills() {
    local skills_file="$1"
    [[ -f "${skills_file}" && -r "${skills_file}" ]] || return 1
    local in_enabled=false

    while IFS= read -r line; do
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        if [[ "${line}" =~ enabled:[[:space:]]*$ ]]; then
            in_enabled=true; continue
        fi
        if ${in_enabled} && [[ "${line}" =~ ^[[:space:]]{0,3}[a-zA-Z] ]] && [[ ! "${line}" =~ ^[[:space:]]*- ]]; then
            in_enabled=false; continue
        fi
        if ${in_enabled} && [[ "${line}" =~ ^[[:space:]]*-[[:space:]]+name:[[:space:]]+(.*) ]]; then
            local slug="${BASH_REMATCH[1]}"; slug="${slug## }"; slug="${slug%% }"
            echo "${slug}"; continue
        fi
        if ${in_enabled} && [[ "${line}" =~ ^[[:space:]]*-[[:space:]]+(.*) ]]; then
            local slug="${BASH_REMATCH[1]}"; slug="${slug## }"; slug="${slug%% }"
            [[ "${slug}" =~ ^[a-zA-Z]+: ]] && continue
            echo "${slug}"
        fi
    done < "${skills_file}"
}
