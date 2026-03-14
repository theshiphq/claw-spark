#!/usr/bin/env bash
# install.sh — clawspark one-click installer.
# Sets up OpenClaw with a local LLM on NVIDIA DGX Spark, Jetson, or RTX hardware.
#
# Quick start:
#   curl -fsSL https://clawspark.dev/install.sh | bash
#
# Or clone and run:
#   git clone https://github.com/saiyam1814/claw-spark && cd claw-spark && bash install.sh
set -euo pipefail

# ── Resolve script directory (works even when piped from curl) ──────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" 2>/dev/null)" &>/dev/null && pwd 2>/dev/null || echo "/tmp/clawspark")"

# ── Parse command-line flags ────────────────────────────────────────────────
CLAWSPARK_DEFAULTS="${CLAWSPARK_DEFAULTS:-false}"
AIR_GAP="false"
FLAG_MODEL=""
FLAG_MESSAGING=""
DEPLOY_MODE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --defaults)
            CLAWSPARK_DEFAULTS="true"
            shift ;;
        --air-gap|--airgap)
            AIR_GAP="true"
            shift ;;
        --model=*)
            FLAG_MODEL="${1#*=}"
            shift ;;
        --messaging=*)
            FLAG_MESSAGING="${1#*=}"
            shift ;;
        -h|--help)
            cat <<HELP
Usage: install.sh [OPTIONS]

Options:
  --defaults           Skip all interactive prompts (use defaults)
  --air-gap            Enable air-gap mode after setup
  --model=<id>         Ollama model ID to use (e.g. qwen3.5:35b-a3b)
  --messaging=<type>   whatsapp | telegram | both | skip
  -h, --help           Show this help
HELP
            exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1 ;;
    esac
done

export CLAWSPARK_DEFAULTS AIR_GAP FLAG_MODEL FLAG_MESSAGING DEPLOY_MODE

# ── Prepare clawspark directory ─────────────────────────────────────────────
CLAWSPARK_DIR="${HOME}/.clawspark"
mkdir -p "${CLAWSPARK_DIR}"
CLAWSPARK_LOG="${CLAWSPARK_DIR}/install.log"
: > "${CLAWSPARK_LOG}"   # truncate / create log

# ── Source library modules ──────────────────────────────────────────────────
_source_lib() {
    local lib_dir="${SCRIPT_DIR}/lib"

    # If running from curl pipe and lib/ doesn't exist, try to download
    if [[ ! -d "${lib_dir}" ]]; then
        lib_dir="${CLAWSPARK_DIR}/lib"
        if [[ ! -d "${lib_dir}" ]]; then
            echo "ERROR: Cannot find lib/ directory. Please clone the repo and run install.sh from there." >&2
            exit 1
        fi
    fi

    local f
    for f in \
        common.sh \
        detect-hardware.sh \
        select-model.sh \
        setup-inference.sh \
        setup-openclaw.sh \
        setup-skills.sh \
        setup-messaging.sh \
        setup-voice.sh \
        setup-tailscale.sh \
        setup-dashboard.sh \
        secure.sh \
        verify.sh \
    ; do
        if [[ -f "${lib_dir}/${f}" ]]; then
            # shellcheck source=/dev/null
            source "${lib_dir}/${f}"
        else
            echo "ERROR: Missing library file: ${lib_dir}/${f}" >&2
            exit 1
        fi
    done

    # Store lib location for the CLI tool later
    CLAWSPARK_LIB_DIR="${lib_dir}"
}

_source_lib

# ── Error trap ──────────────────────────────────────────────────────────────
_on_error() {
    local exit_code=$?
    local line_no=$1
    log_error "Installation failed at line ${line_no} (exit code ${exit_code})."
    log_error "Check the log for details: ${CLAWSPARK_LOG}"
    printf '\n  %sIf this looks like a bug, please open an issue at:%s\n' "${YELLOW}" "${RESET}"
    printf '  https://github.com/saiyam1814/claw-spark/issues\n\n'
    exit "${exit_code}"
}
trap '_on_error ${LINENO}' ERR

# ── Detect if stdin is a terminal (for curl-pipe support) ───────────────────
if [[ ! -t 0 ]]; then
    # Piped from curl — force defaults mode if user can't interact
    if [[ ! -t 1 ]]; then
        CLAWSPARK_DEFAULTS="true"
    fi
fi

# ── ASCII banner ────────────────────────────────────────────────────────────
_show_banner() {
    printf '%s' "${RED}"
    cat <<'BANNER'

          ___  _       ___  __      __  ___  ___    ___   ___  _  __
         / __|| |     /   \\ \ /\ / / / __|| _ \  /   \ | _ \| |/ /
        | (__ | |__  | (_) |\ V  V /  \__ \|  _/ | (_) ||   /|   <
         \___||____| |\___/  \_/\_/   |___/|_|    \___/ |_|_\|_|\_\
                     |_|
BANNER
    printf '%s' "${RESET}"
    printf '%s' "${CYAN}"
    cat <<'CLAW'
                              _____
                             /     \
                            / () () \
                           |  .____.  |
                            \  \__/  /
                      ___    \______/    ___
                     /   '-..__  __..-''   \
                    /  .--._  ''  _.---.  \
                   |  /  ___\    /___   \  |
                   | |  (    \  /    )  |  |
                    \ \  '---'/\\'---'  / /
                     '.\_    /  \    _/.'
                        '---'    '---'
CLAW
    printf '%s' "${RESET}"
    printf '\n'
    printf '  %s%sOne-click AI agent setup for NVIDIA hardware%s\n' "${BOLD}" "${BLUE}" "${RESET}"
    printf '  %sPowered by OpenClaw + Ollama%s\n\n' "${CYAN}" "${RESET}"
    hr
}

# ── Step 1: Banner ─────────────────────────────────────────────────────────
log_info "Step 1/14: Welcome"
_show_banner

# ════════════════════════════════════════════════════════════════════════════
#  INSTALLATION FLOW
# ════════════════════════════════════════════════════════════════════════════

# ── Step 2: Hardware detection ──────────────────────────────────────────────
log_info "Step 2/14: Detecting hardware"
detect_hardware

# ── Step 3: Model selection ─────────────────────────────────────────────────
log_info "Step 3/14: Selecting model"
select_model

# ── Step 4: Deployment mode ─────────────────────────────────────────────────
log_info "Step 4/14: Deployment mode"
if [[ -z "${DEPLOY_MODE}" ]]; then
    if prompt_yn "Use cloud APIs as fallback? (requires API key)" "n"; then
        DEPLOY_MODE="hybrid"
    else
        DEPLOY_MODE="local"
    fi
fi
export DEPLOY_MODE
log_info "Deploy mode: ${DEPLOY_MODE}"

# ── Step 5: Messaging preference ───────────────────────────────────────────
log_info "Step 5/14: Messaging preference"
if [[ -z "${FLAG_MESSAGING}" ]]; then
    msg_opts=("WhatsApp" "Telegram" "Both" "Skip")
    FLAG_MESSAGING=$(prompt_choice "Connect a messaging platform? (Web UI is always available)" msg_opts 3)
fi
export FLAG_MESSAGING
log_info "Messaging: ${FLAG_MESSAGING}"

hr
printf '\n  %s%sBeginning installation...%s\n\n' "${BOLD}" "${GREEN}" "${RESET}"

# ── Step 6: Inference engine ────────────────────────────────────────────────
log_info "Step 6/14: Setting up inference engine"
setup_inference

# ── Step 7: OpenClaw ────────────────────────────────────────────────────────
log_info "Step 7/14: Installing OpenClaw"
setup_openclaw

# ── Step 8: Skills ──────────────────────────────────────────────────────────
log_info "Step 8/14: Installing skills"
setup_skills

# ── Step 9: Voice ──────────────────────────────────────────────────────────
log_info "Step 9/14: Setting up voice"
setup_voice

# ── Step 10: Messaging ─────────────────────────────────────────────────────
log_info "Step 10/14: Setting up messaging"
setup_messaging

# ── Step 11: Tailscale ─────────────────────────────────────────────────────
log_info "Step 11/14: Setting up Tailscale"
setup_tailscale

# ── Step 12: Dashboard ─────────────────────────────────────────────────────
log_info "Step 12/14: Setting up dashboard"
setup_dashboard

# ── Step 13: Security ──────────────────────────────────────────────────────
log_info "Step 13/14: Applying security"
secure_setup

# ── Step 14: Verification ──────────────────────────────────────────────────
log_info "Step 14/14: Verifying installation"
verify_installation

# ── Install the clawspark CLI tool ──────────────────────────────────────────
if [[ -f "${SCRIPT_DIR}/clawspark" ]]; then
    log_info "Installing clawspark CLI to /usr/local/bin..."
    sudo cp "${SCRIPT_DIR}/clawspark" /usr/local/bin/clawspark 2>/dev/null || {
        cp "${SCRIPT_DIR}/clawspark" "${CLAWSPARK_DIR}/clawspark"
        log_warn "Could not write to /usr/local/bin — CLI saved to ${CLAWSPARK_DIR}/clawspark"
    }
    sudo chmod +x /usr/local/bin/clawspark 2>/dev/null || true
fi

# Copy lib to CLAWSPARK_DIR for the CLI to source later
if [[ -d "${SCRIPT_DIR}/lib" ]]; then
    cp -r "${SCRIPT_DIR}/lib" "${CLAWSPARK_DIR}/"
fi

# ── Final message ───────────────────────────────────────────────────────────
printf '\n'
hr
printf '\n'
printf '  %s%s' "${GREEN}" "${BOLD}"
cat <<'DONE'
   __   __            _                 _ _            _   _
   \ \ / /___  _  _  ( )_ _ ___   __ _| | |  ___ ___ | |_| |
    \ V // _ \| || | |/| '_/ -_) / _` | | | (_-</ -_)|  _|_|
     |_| \___/ \_,_|   |_| \___| \__,_|_|_| /__/\___| \__(_)
DONE
printf '%s\n' "${RESET}"

_final_urls=()
_final_urls+=("Chat UI: http://localhost:18789/__openclaw__/canvas/")
_final_urls+=("Dashboard: http://localhost:8900")
if [[ -f "${CLAWSPARK_DIR}/tailscale.url" ]]; then
    _final_urls+=("Tailscale: $(cat "${CLAWSPARK_DIR}/tailscale.url")")
fi

print_box \
    "${BOLD}Next Steps${RESET}" \
    "" \
    "${_final_urls[@]}" \
    "" \
    "1. Open the Chat UI in your browser to talk to your agent" \
    "2. Or send a message via WhatsApp or Telegram" \
    "3. Manage your setup: ${CYAN}clawspark status${RESET}" \
    "4. Add skills: ${CYAN}clawspark skills add <name>${RESET}" \
    "5. View logs: ${CYAN}clawspark logs${RESET}" \
    "" \
    "Full log: ${CLAWSPARK_LOG}"

printf '\n  %sHappy hacking!%s\n\n' "${CYAN}" "${RESET}"
