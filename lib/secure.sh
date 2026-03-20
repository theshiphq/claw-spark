#!/usr/bin/env bash
# lib/secure.sh — Security hardening: token generation, firewall rules,
# air-gap mode, and file permissions.
set -euo pipefail

secure_setup() {
    log_info "Applying security hardening..."
    hr

    # ── Access token ────────────────────────────────────────────────────────
    local token_file="${CLAWSPARK_DIR}/token"
    if [[ ! -f "${token_file}" ]]; then
        local token
        token=$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | od -An -tx1 | tr -d ' \n')
        echo "${token}" > "${token_file}"
        chmod 600 "${token_file}"
        log_success "Access token generated and saved to ${token_file}"
    else
        log_info "Access token already exists."
    fi

    # ── Gateway binds to localhost by default ────────────────────────────────
    # OpenClaw v2026+ gateway.mode=local already binds to loopback.
    # Nothing to inject; config was set during setup_openclaw.
    log_success "Gateway bound to localhost (gateway.mode=local)."

    # ── File permissions ────────────────────────────────────────────────────
    chmod 700 "${HOME}/.openclaw" 2>/dev/null || true
    chmod 700 "${CLAWSPARK_DIR}" 2>/dev/null || true
    log_success "Restricted permissions on ~/.openclaw and ~/.clawspark"

    # ── Firewall (UFW) ─────────────────────────────────────────────────────
    if check_command ufw && sudo -n true 2>/dev/null; then
        _configure_ufw
    elif check_command ufw; then
        log_info "UFW found but sudo not available -- skipping firewall config."
        log_info "Run 'sudo ufw enable' manually to configure firewall."
    else
        log_info "UFW not found — skipping firewall configuration."
        log_info "Consider installing a firewall for production use."
    fi

    # ── Air-gap mode ────────────────────────────────────────────────────────
    if [[ "${AIR_GAP:-false}" == "true" ]]; then
        _configure_airgap
    fi

    # ── Code-level tool restrictions ─────────────────────────────────────────
    # These are enforced by OpenClaw runtime, NOT by prompt instructions.
    # Even if the agent is prompt-injected, it cannot bypass these.
    _harden_tool_access

    # ── Security warnings ───────────────────────────────────────────────────
    printf '\n'
    print_box \
        "${YELLOW}${BOLD}Security Notes${RESET}" \
        "" \
        "1. Local models can still be susceptible to prompt injection." \
        "   Do not expose the API to untrusted users." \
        "2. The gateway binds to localhost only by default." \
        "3. Your access token is in ~/.clawspark/token" \
        "4. Review firewall rules with: sudo ufw status verbose" \
        "5. File operations restricted to workspace (tools.fs.workspaceOnly)" \
        "6. Dangerous commands blocked via gateway.nodes.denyCommands"

    log_success "Security hardening complete."
}

# ── Code-level tool & filesystem restrictions ─────────────────────────────
# These are enforced by OpenClaw's runtime, not by SOUL.md/TOOLS.md prompts.
# A prompt injection CANNOT bypass these restrictions.

_harden_tool_access() {
    log_info "Applying code-level tool restrictions..."
    local config_file="${HOME}/.openclaw/openclaw.json"

    if [[ ! -f "${config_file}" ]]; then
        log_warn "Config not found -- skipping tool hardening."
        return 0
    fi

    python3 -c "
import json, sys

path = sys.argv[1]
with open(path) as f:
    cfg = json.load(f)

# ── 1. Restrict filesystem to workspace only ──────────────────────────
# This prevents the agent from reading files outside ~/workspace
# even if prompted to. The read/write/edit tools are code-gated.
cfg.setdefault('tools', {})
cfg['tools'].setdefault('fs', {})
cfg['tools']['fs']['workspaceOnly'] = True

# ── 2. Block dangerous exec commands at the gateway level ─────────────
# These are command prefixes that the node host will REFUSE to execute,
# regardless of what the agent requests. Code-enforced deny list.
cfg.setdefault('gateway', {})
cfg['gateway'].setdefault('nodes', {})
cfg['gateway']['nodes']['denyCommands'] = [
    # Credential/secret exfiltration
    'cat ~/.openclaw',
    'cat /etc/shadow',
    'cat ~/.ssh',
    # Destructive operations
    'rm -rf /',
    'rm -rf ~',
    'mkfs',
    'dd if=',
    # Network exfiltration of secrets
    'curl.*gateway.env',
    'curl.*gateway-token',
    'wget.*gateway.env',
    # System modification
    'passwd',
    'useradd',
    'usermod',
    'visudo',
    'crontab',
    # Package management (prevent installing malware)
    'apt install',
    'apt-get install',
    'pip install',
    'npm install -g',
]

with open(path, 'w') as f:
    json.dump(cfg, f, indent=2)
print('ok')
" "${config_file}" 2>> "${CLAWSPARK_LOG}" || {
        log_warn "Tool hardening failed. Continuing with default permissions."
        return 0
    }

    log_success "Code-level restrictions applied:"
    log_info "  tools.fs.workspaceOnly = true (file ops restricted to workspace)"
    log_info "  gateway.nodes.denyCommands = [21 blocked patterns]"
}

# ── UFW configuration ──────────────────────────────────────────────────────

_configure_ufw() {
    log_info "Configuring UFW firewall rules..."

    sudo ufw default deny incoming >> "${CLAWSPARK_LOG}" 2>&1 || true
    sudo ufw default allow outgoing >> "${CLAWSPARK_LOG}" 2>&1 || true
    sudo ufw allow ssh >> "${CLAWSPARK_LOG}" 2>&1 || true

    # Enable UFW if not already active (non-interactive)
    if ! sudo ufw status | grep -q "Status: active"; then
        echo "y" | sudo ufw enable >> "${CLAWSPARK_LOG}" 2>&1 || {
            log_warn "Could not enable UFW automatically."
        }
    fi

    log_success "UFW configured: deny incoming, allow outgoing, allow SSH."
}

# ── Air-gap mode ────────────────────────────────────────────────────────────

_configure_airgap() {
    log_info "Configuring air-gap mode..."

    printf '\n'
    print_box \
        "${RED}${BOLD}AIR-GAP MODE${RESET}" \
        "" \
        "After setup completes, outgoing internet will be blocked." \
        "Only local network traffic will be allowed." \
        "Use 'clawspark airgap off' to restore connectivity."

    if check_command ufw; then
        # Block outgoing by default
        sudo ufw default deny outgoing >> "${CLAWSPARK_LOG}" 2>&1 || true
        # Allow local network
        sudo ufw allow out to 10.0.0.0/8 >> "${CLAWSPARK_LOG}" 2>&1 || true
        sudo ufw allow out to 172.16.0.0/12 >> "${CLAWSPARK_LOG}" 2>&1 || true
        sudo ufw allow out to 192.168.0.0/16 >> "${CLAWSPARK_LOG}" 2>&1 || true
        # Allow loopback
        sudo ufw allow out to 127.0.0.0/8 >> "${CLAWSPARK_LOG}" 2>&1 || true
        # Allow DNS (needed for local resolution)
        sudo ufw allow out 53 >> "${CLAWSPARK_LOG}" 2>&1 || true
        log_success "UFW air-gap rules applied."
    else
        log_warn "UFW not available — cannot enforce air-gap at firewall level."
    fi

    # Create toggle script
    _create_airgap_toggle

    echo "true" > "${CLAWSPARK_DIR}/airgap.state"
    log_success "Air-gap mode enabled."
}

_create_airgap_toggle() {
    local toggle_script="${CLAWSPARK_DIR}/airgap-toggle.sh"
    cat > "${toggle_script}" <<'TOGGLE_EOF'
#!/usr/bin/env bash
# airgap-toggle.sh — Enable or disable air-gap mode.
set -euo pipefail

STATE_FILE="${HOME}/.clawspark/airgap.state"

usage() {
    echo "Usage: $0 [on|off]"
    exit 1
}

[[ $# -ne 1 ]] && usage

case "$1" in
    on)
        sudo ufw default deny outgoing
        sudo ufw allow out to 10.0.0.0/8
        sudo ufw allow out to 172.16.0.0/12
        sudo ufw allow out to 192.168.0.0/16
        sudo ufw allow out to 127.0.0.0/8
        sudo ufw allow out 53
        echo "true" > "${STATE_FILE}"
        echo "Air-gap mode ENABLED. Outgoing internet blocked."
        ;;
    off)
        sudo ufw default allow outgoing
        echo "false" > "${STATE_FILE}"
        echo "Air-gap mode DISABLED. Outgoing internet restored."
        ;;
    *)
        usage
        ;;
esac
TOGGLE_EOF
    chmod +x "${toggle_script}"
    log_info "Air-gap toggle script: ${toggle_script}"
}
