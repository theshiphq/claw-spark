#!/usr/bin/env bash
# lib/setup-messaging.sh — Configures WhatsApp and/or Telegram messaging channels.
# Reads FLAG_MESSAGING (set by install.sh or interactive prompt).
set -euo pipefail

setup_messaging() {
    log_info "Setting up messaging channels..."
    hr

    local messaging_choice="${FLAG_MESSAGING:-}"

    # ── Prompt if not set via flag ──────────────────────────────────────────
    if [[ -z "${messaging_choice}" ]]; then
        local options=("WhatsApp" "Telegram" "Both" "Skip")
        messaging_choice=$(prompt_choice "Which messaging channel(s) would you like?" options 0)
    fi

    messaging_choice=$(to_lower "${messaging_choice}")
    export MESSAGING_CHOICE="${messaging_choice}"

    case "${messaging_choice}" in
        whatsapp)
            _setup_whatsapp
            ;;
        telegram)
            _setup_telegram
            ;;
        both)
            _setup_whatsapp
            _setup_telegram
            ;;
        skip)
            log_info "Messaging setup skipped."
            ;;
        *)
            log_warn "Unknown messaging option '${messaging_choice}' -- skipping."
            ;;
    esac

    # Always start the gateway (Chat UI needs it even without messaging)
    _start_gateway
}

# ── WhatsApp ────────────────────────────────────────────────────────────────

_setup_whatsapp() {
    log_info "Configuring WhatsApp..."
    printf '\n'
    printf '  %s%sWhatsApp Setup%s\n' "${BOLD}" "${GREEN}" "${RESET}"
    printf '  OpenClaw uses the Baileys library for WhatsApp Web linking.\n'
    printf '  You will need to scan a QR code from your phone.\n'
    printf '  Open WhatsApp on your phone > Linked Devices > Link a Device\n\n'
    printf '  %s%sNote:%s WhatsApp linking depends on the upstream Baileys library.\n' "${BOLD}" "${YELLOW}" "${RESET}"
    printf '  If linking fails, the Chat UI still works at:\n'
    printf '    http://localhost:18789/__openclaw__/canvas/\n'
    printf '  You can also use Telegram as an alternative messaging channel.\n\n'

    if [[ "${CLAWSPARK_DEFAULTS}" == "true" ]]; then
        log_warn "Cannot complete WhatsApp QR scan in --defaults mode."
        log_info "Run 'openclaw channels login' later to link WhatsApp."
        return 0
    fi

    # Ask for the user's WhatsApp phone number (for allowlist security)
    printf '  Enter your WhatsApp phone number (with country code, e.g. 919878251239):\n'
    printf '  > '
    local wa_number=""
    read -r wa_number </dev/tty || true
    wa_number="${wa_number//[^0-9]/}"  # strip non-digits

    # Enable WhatsApp channel in config with security + message batching
    openclaw config set channels.whatsapp.enabled true >> "${CLAWSPARK_LOG}" 2>&1 || true
    openclaw config set channels.whatsapp.debounceMs 8000 >> "${CLAWSPARK_LOG}" 2>&1 || true
    openclaw config set channels.whatsapp.groupPolicy disabled >> "${CLAWSPARK_LOG}" 2>&1 || true

    # Set allowlist so only the owner can interact (no auto-replies to strangers)
    if [[ -n "${wa_number}" ]]; then
        openclaw config set channels.whatsapp.allowFrom "[\"${wa_number}@s.whatsapp.net\"]" >> "${CLAWSPARK_LOG}" 2>&1 || true
        openclaw config set channels.whatsapp.dmPolicy allowlist >> "${CLAWSPARK_LOG}" 2>&1 || true
        log_success "WhatsApp locked to your number: +${wa_number}"
    else
        log_warn "No phone number provided. Using pairing mode (strangers will get auto-replies)."
        openclaw config set channels.whatsapp.dmPolicy pairing >> "${CLAWSPARK_LOG}" 2>&1 || true
    fi

    printf '\n'
    printf '  Now scan the QR code with your phone:\n'
    printf '  Open WhatsApp > Linked Devices > Link a Device\n\n'
    printf '  Press Enter when ready...'
    read -r </dev/tty || true

    # Source Ollama env so the gateway can start if needed
    local env_file="${HOME}/.openclaw/gateway.env"
    if [[ -f "${env_file}" ]]; then set +e; set -a; source "${env_file}" 2>/dev/null; set +a; set -e; fi

    # Use the channels login command for WhatsApp
    openclaw channels login --channel whatsapp --verbose 2>&1 | tee -a "${CLAWSPARK_LOG}" || {
        log_warn "WhatsApp linking exited with an error."
    }

    printf '\n'
    if prompt_yn "  Did you successfully link WhatsApp?" "y"; then
        log_success "WhatsApp linked."
    else
        log_warn "WhatsApp not linked. You can try again later: openclaw channels login"
        log_info "The Chat UI is always available at: http://localhost:18789/__openclaw__/canvas/"
    fi
}

# ── Telegram ────────────────────────────────────────────────────────────────

_setup_telegram() {
    log_info "Configuring Telegram..."
    printf '\n'
    printf '  %s%sTelegram Setup%s\n' "${BOLD}" "${GREEN}" "${RESET}"
    printf '  The OpenClaw wizard will guide you through Telegram bot setup.\n'
    printf '  You will need a bot token from @BotFather on Telegram.\n\n'

    if [[ "${CLAWSPARK_DEFAULTS}" == "true" ]]; then
        log_warn "Cannot configure Telegram bot in --defaults mode."
        log_info "Run 'openclaw configure --section channels' later."
        return 0
    fi

    # Source Ollama env
    local env_file="${HOME}/.openclaw/gateway.env"
    if [[ -f "${env_file}" ]]; then set +e; set -a; source "${env_file}" 2>/dev/null; set +a; set -e; fi

    openclaw configure --section channels 2>&1 | tee -a "${CLAWSPARK_LOG}" || {
        log_warn "Channel setup exited with an error. You can configure Telegram manually later."
        return 0
    }
    log_success "Telegram bot configured."
}

# ── Gateway ─────────────────────────────────────────────────────────────────

_start_gateway() {
    log_info "Starting OpenClaw gateway..."
    local gateway_log="${CLAWSPARK_DIR}/gateway.log"
    local gateway_pid_file="${CLAWSPARK_DIR}/gateway.pid"

    # Kill existing gateway if running
    if [[ -f "${gateway_pid_file}" ]]; then
        local old_pid
        old_pid=$(cat "${gateway_pid_file}")
        if kill -0 "${old_pid}" 2>/dev/null; then
            log_info "Stopping existing gateway (PID ${old_pid})..."
            kill "${old_pid}" 2>/dev/null || true
            sleep 1
        fi
    fi

    # Source Ollama provider credentials
    local env_file="${HOME}/.openclaw/gateway.env"
    if [[ -f "${env_file}" ]]; then set +e; set -a; source "${env_file}" 2>/dev/null; set +a; set -e; fi

    nohup openclaw gateway run --bind loopback > "${gateway_log}" 2>&1 &
    local gw_pid=$!
    echo "${gw_pid}" > "${gateway_pid_file}"

    sleep 3
    if kill -0 "${gw_pid}" 2>/dev/null; then
        log_success "Gateway running (PID ${gw_pid}). Logs: ${gateway_log}"
    else
        log_warn "Gateway process exited unexpectedly. Check ${gateway_log}."
        log_warn "You can start it manually later: clawspark restart"
        return 0
    fi

    # Node host will be started later (after all config changes are done)
    # to avoid gateway restart (1012) killing it mid-setup.
}

_start_node_host() {
    log_info "Starting node host (agent execution engine)..."
    local node_log="${CLAWSPARK_DIR}/node.log"
    local node_pid_file="${CLAWSPARK_DIR}/node.pid"

    # Ensure workspace directory exists and is writable
    local workspace="${HOME}/workspace"
    mkdir -p "${workspace}"
    openclaw config set agents.defaults.workspace "${workspace}" >> "${CLAWSPARK_LOG}" 2>&1 || true

    # Kill existing node host if running
    if [[ -f "${node_pid_file}" ]]; then
        local old_pid
        old_pid=$(cat "${node_pid_file}")
        kill "${old_pid}" 2>/dev/null || true
        sleep 1
    fi

    local env_file="${HOME}/.openclaw/gateway.env"
    if [[ -f "${env_file}" ]]; then set +e; set -a; source "${env_file}" 2>/dev/null; set +a; set -e; fi

    nohup openclaw node run --host 127.0.0.1 --port 18789 > "${node_log}" 2>&1 &
    local node_pid=$!
    echo "${node_pid}" > "${node_pid_file}"

    # Wait for the node to register and create a pairing request
    sleep 5

    # Auto-approve pending device requests (this is a local single-user install)
    local attempt
    for attempt in 1 2 3; do
        local device_output
        device_output=$(openclaw devices list 2>/dev/null || echo "")

        # Only extract UUIDs from lines that contain "pending" or "Pending"
        # to avoid approving already-paired devices or matching non-request UUIDs
        local request_ids
        request_ids=$(echo "${device_output}" | grep -iE 'pending|request' | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' || true)
        # Fallback: if no "pending" lines but there are UUIDs in a "Requests" section, try those
        if [[ -z "${request_ids}" ]]; then
            request_ids=$(echo "${device_output}" | sed -n '/^Request/,/^$/p' | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' || true)
        fi

        if [[ -n "${request_ids}" ]]; then
            local rid
            for rid in ${request_ids}; do
                openclaw devices approve "${rid}" >> "${CLAWSPARK_LOG}" 2>&1 && \
                    log_info "Auto-approved device: ${rid}" || true
            done
            # Restart node host after approval so it reconnects with proper auth
            kill "${node_pid}" 2>/dev/null || true
            sleep 2
            nohup openclaw node run --host 127.0.0.1 --port 18789 > "${node_log}" 2>&1 &
            node_pid=$!
            echo "${node_pid}" > "${node_pid_file}"
            sleep 3
            break
        fi
        sleep 2
    done

    if kill -0 "${node_pid}" 2>/dev/null; then
        log_success "Node host running (PID ${node_pid})."
    else
        log_warn "Node host failed to start. Agent will work without exec/browser tools."
        log_warn "You can start it manually: openclaw node run --host 127.0.0.1 --port 18789"
    fi
}
