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

# ── Bootstrap: if piped from curl, clone the repo and re-exec ─────────────
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd 2>/dev/null || true)"
fi

if [[ -z "${SCRIPT_DIR}" ]] || [[ ! -d "${SCRIPT_DIR}/lib" ]]; then
    # Running via curl pipe -- no lib/ available, need to clone
    CLONE_DIR="$(mktemp -d)/claw-spark"
    echo "Downloading clawspark..."
    if command -v git &>/dev/null; then
        git clone --depth 1 https://github.com/saiyam1814/claw-spark.git "${CLONE_DIR}" 2>/dev/null
    else
        # Fallback: download tarball if git is not available
        mkdir -p "${CLONE_DIR}"
        curl -fsSL https://github.com/saiyam1814/claw-spark/archive/refs/heads/main.tar.gz \
            | tar xz --strip-components=1 -C "${CLONE_DIR}"
    fi
    # Re-exec from the cloned repo, reconnecting stdin to the terminal
    # so interactive prompts work (curl pipe leaves stdin at EOF).
    # Prefer Homebrew bash on macOS (system bash is 3.2, too old).
    _REEXEC_BASH="bash"
    if [[ "$(uname)" == "Darwin" ]]; then
        if [[ -x /opt/homebrew/bin/bash ]]; then
            _REEXEC_BASH=/opt/homebrew/bin/bash
        elif [[ -x /usr/local/bin/bash ]]; then
            _REEXEC_BASH=/usr/local/bin/bash
        fi
    fi
    exec "${_REEXEC_BASH}" "${CLONE_DIR}/install.sh" "$@" </dev/tty
fi

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

# ── Require bash 4.2+ (macOS ships 3.2 which lacks nameref, ${var,,}, etc.) ─
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]] || { [[ "${BASH_VERSINFO[0]}" -eq 4 ]] && [[ "${BASH_VERSINFO[1]}" -lt 2 ]]; }; then
    echo ""
    echo "ERROR: Bash 4.2+ is required (you have ${BASH_VERSION})."
    echo ""
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "macOS ships with bash 3.2. Install modern bash with Homebrew:"
        echo ""
        echo "  brew install bash"
        echo ""
        echo "Then re-run the installer with:"
        echo ""
        echo "  /opt/homebrew/bin/bash <(curl -fsSL https://clawspark.dev/install.sh)"
        echo ""
    else
        echo "Please install bash 4.2+ and re-run the installer."
    fi
    exit 1
fi

# ── Prepare clawspark directory ─────────────────────────────────────────────
CLAWSPARK_DIR="${HOME}/.clawspark"
mkdir -p "${CLAWSPARK_DIR}"
CLAWSPARK_LOG="${CLAWSPARK_DIR}/install.log"
: > "${CLAWSPARK_LOG}"   # truncate / create log

# ── Source library modules ──────────────────────────────────────────────────
_source_lib() {
    local lib_dir="${SCRIPT_DIR}/lib"

    if [[ ! -d "${lib_dir}" ]]; then
        echo "ERROR: Cannot find lib/ directory at ${lib_dir}" >&2
        exit 1
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
        setup-models.sh \
        setup-mcp.sh \
        setup-browser.sh \
        setup-sandbox.sh \
        setup-systemd.sh \
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
log_info "Step 1/19: Welcome"
_show_banner

# ════════════════════════════════════════════════════════════════════════════
#  INSTALLATION FLOW
# ════════════════════════════════════════════════════════════════════════════

# ── Cache sudo credentials upfront so the install never pauses for password ──
if sudo -v 2>/dev/null; then
    log_info "sudo credentials cached."
    # Keep sudo alive in background for the duration of the install
    ( while true; do sudo -n true 2>/dev/null; sleep 50; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill ${SUDO_KEEPALIVE_PID} 2>/dev/null; _on_error ${LINENO}' ERR
    trap 'kill ${SUDO_KEEPALIVE_PID} 2>/dev/null' EXIT
else
    log_warn "sudo not available. Some steps (firewall, systemd) will be skipped."
fi

# ── Step 2: Hardware detection ──────────────────────────────────────────────
log_info "Step 2/19: Detecting hardware"
detect_hardware

# ── Step 3: Model selection ─────────────────────────────────────────────────
log_info "Step 3/19: Selecting model"
select_model

# ── Step 4: Deployment mode ─────────────────────────────────────────────────
log_info "Step 4/19: Deployment mode"
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
log_info "Step 5/19: Messaging preference"
if [[ -z "${FLAG_MESSAGING}" ]]; then
    msg_opts=("WhatsApp" "Telegram" "Both" "Skip")
    FLAG_MESSAGING=$(prompt_choice "Connect a messaging platform? (Web UI is always available)" msg_opts 3)
fi
# Lowercase for consistent matching downstream
FLAG_MESSAGING=$(to_lower "${FLAG_MESSAGING}")
export FLAG_MESSAGING
log_info "Messaging: ${FLAG_MESSAGING}"

hr
printf '\n  %s%sBeginning installation...%s\n\n' "${BOLD}" "${GREEN}" "${RESET}"

# ── Step 6: Inference engine ────────────────────────────────────────────────
log_info "Step 6/19: Setting up inference engine"
setup_inference

# ── Step 7: OpenClaw ────────────────────────────────────────────────────────
log_info "Step 7/19: Installing OpenClaw"
setup_openclaw

# ── Install the clawspark CLI early so it is available for troubleshooting ──
if [[ -f "${SCRIPT_DIR}/clawspark" ]]; then
    sudo cp "${SCRIPT_DIR}/clawspark" /usr/local/bin/clawspark 2>/dev/null || {
        cp "${SCRIPT_DIR}/clawspark" "${CLAWSPARK_DIR}/clawspark" 2>/dev/null || true
    }
    sudo chmod +x /usr/local/bin/clawspark 2>/dev/null || true
fi
if [[ -d "${SCRIPT_DIR}/lib" ]]; then
    cp -r "${SCRIPT_DIR}/lib" "${CLAWSPARK_DIR}/"
fi
if [[ -d "${SCRIPT_DIR}/configs" ]]; then
    cp -r "${SCRIPT_DIR}/configs" "${CLAWSPARK_DIR}/"
fi

# ── Step 8: Skills ──────────────────────────────────────────────────────────
log_info "Step 8/19: Installing skills"
setup_skills

# ── Step 9: Voice ──────────────────────────────────────────────────────────
log_info "Step 9/19: Setting up voice"
setup_voice

# ── Step 10: Messaging ─────────────────────────────────────────────────────
log_info "Step 10/19: Setting up messaging"
setup_messaging

# ── Step 11: Tailscale ─────────────────────────────────────────────────────
log_info "Step 11/19: Setting up Tailscale"
setup_tailscale

# ── Step 12: Dashboard ─────────────────────────────────────────────────────
log_info "Step 12/19: Setting up dashboard"
setup_dashboard || log_warn "Dashboard setup had issues -- continuing with install."

# ── Step 13: Vision & multi-model ──────────────────────────────────────────
log_info "Step 13/19: Configuring vision and multi-model support"
setup_models || log_warn "Model configuration had issues -- continuing."

# ── Step 14: MCP servers (diagrams, memory, reasoning) ───────────────────
log_info "Step 14/19: Setting up MCP servers"
setup_mcp || log_warn "MCP setup had issues -- continuing."

# ── Step 15: Browser automation ────────────────────────────────────────────
log_info "Step 15/19: Setting up browser automation"
setup_browser || log_warn "Browser setup had issues -- continuing."

# ── Step 16: Docker sandbox ────────────────────────────────────────────────
log_info "Step 16/19: Setting up Docker sandbox"
setup_sandbox || log_warn "Sandbox setup had issues -- continuing."

# ── Step 17: Systemd services ──────────────────────────────────────────────
log_info "Step 17/19: Creating systemd services for auto-start on boot"
setup_systemd_services || log_warn "Systemd setup had issues -- services will use PID management."

# ── Step 18: Security ──────────────────────────────────────────────────────
log_info "Step 18/19: Applying security"
secure_setup

# ── Start node host (after all config changes are done) ───────────────────
# Skip if systemd already started the node host (step 16)
if check_command systemctl && systemctl is-active --quiet clawspark-nodehost.service 2>/dev/null; then
    log_info "Node host already running via systemd."
else
    log_info "Starting node host..."
    _start_node_host || log_warn "Node host failed to start -- you can start it with: clawspark start"
fi

# ── Step 18: Verification ──────────────────────────────────────────────────
log_info "Step 19/19: Verifying installation"
verify_installation

# ── Final CLI refresh (picks up any changes made during install) ──────────
if [[ -f "${SCRIPT_DIR}/clawspark" ]]; then
    sudo cp "${SCRIPT_DIR}/clawspark" /usr/local/bin/clawspark 2>/dev/null || true
    sudo chmod +x /usr/local/bin/clawspark 2>/dev/null || true
fi
[[ -d "${SCRIPT_DIR}/lib" ]] && cp -r "${SCRIPT_DIR}/lib" "${CLAWSPARK_DIR}/"
[[ -d "${SCRIPT_DIR}/configs" ]] && cp -r "${SCRIPT_DIR}/configs" "${CLAWSPARK_DIR}/"

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
    "4. Install skill packs: ${CYAN}clawspark skills pack research${RESET}" \
    "5. Switch models: ${CYAN}clawspark model list${RESET}" \
    "6. Enable sandbox: ${CYAN}clawspark sandbox on${RESET}" \
    "7. View logs: ${CYAN}clawspark logs${RESET}" \
    "" \
    "Services auto-start on boot (systemd)." \
    "Full log: ${CLAWSPARK_LOG}"

printf '\n  %sHappy hacking!%s\n\n' "${CYAN}" "${RESET}"
