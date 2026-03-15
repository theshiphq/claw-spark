#!/usr/bin/env bash
# lib/setup-tailscale.sh — Optional Tailscale setup for secure remote access
# to OpenClaw and ClawMetry from anywhere on your Tailnet.
# Uses `tailscale serve` as a reverse proxy -- does NOT restart the gateway.
set -euo pipefail

setup_tailscale() {
    log_info "Tailscale setup (optional)..."
    hr

    # ── Ask if user wants Tailscale ──────────────────────────────────────────
    if ! prompt_yn "Would you like to set up Tailscale for secure remote access?" "n"; then
        log_info "Tailscale setup skipped."
        return 0
    fi

    # ── Install Tailscale if not present ─────────────────────────────────────
    if check_command tailscale; then
        log_success "Tailscale is already installed."
    else
        log_info "Installing Tailscale..."
        (curl -fsSL https://tailscale.com/install.sh | sh) >> "${CLAWSPARK_LOG}" 2>&1 &
        spinner $! "Installing Tailscale..."

        if ! check_command tailscale; then
            log_error "Tailscale installation failed. Check ${CLAWSPARK_LOG}."
            return 1
        fi
        log_success "Tailscale installed."
    fi

    # ── Connect to Tailnet ───────────────────────────────────────────────────
    if tailscale status &>/dev/null; then
        log_success "Tailscale is connected."
    else
        log_info "Tailscale is not connected. Starting Tailscale..."
        sudo tailscale up 2>&1 | tee -a "${CLAWSPARK_LOG}" || {
            log_error "Failed to connect Tailscale. Run 'sudo tailscale up' manually."
            return 1
        }

        if tailscale status &>/dev/null; then
            log_success "Tailscale connected."
        else
            log_error "Tailscale did not connect. Check 'tailscale status' for details."
            return 1
        fi
    fi

    # ── Get the Tailscale FQDN for this machine ───────────────────────────────
    local ts_fqdn=""
    # Method 1: tailscale status --json parsed with python3 (most reliable)
    ts_fqdn=$(tailscale status --json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
self_key = data.get('Self', {})
dns_name = self_key.get('DNSName', '')
# DNSName ends with a trailing dot, strip it
print(dns_name.rstrip('.'))
" 2>/dev/null || echo "")

    # Method 2: tailscale whois --self
    if [[ -z "${ts_fqdn}" ]]; then
        ts_fqdn=$(tailscale whois --self 2>/dev/null \
            | grep -i 'Name:' | head -1 | awk '{print $2}' \
            | sed 's/\.$//' || echo "")
    fi

    # Method 3: construct from IP
    if [[ -z "${ts_fqdn}" ]]; then
        local ts_ip
        ts_ip=$(tailscale ip -4 2>/dev/null || echo "")
        if [[ -n "${ts_ip}" ]]; then
            ts_fqdn="${ts_ip}"
        else
            ts_fqdn="your-machine"
        fi
    fi

    log_info "Tailscale FQDN: ${ts_fqdn}"

    # ── Use tailscale serve as a reverse proxy ─────────────────────────────────
    # This proxies HTTPS on the Tailnet to the local gateway on localhost:18789.
    # The gateway and node host keep running unchanged -- no restart needed.
    #
    # tailscale serve can hang if Serve is not enabled on the tailnet (it prints
    # a URL and waits). We check for that first and use a short timeout.
    log_info "Setting up tailscale serve to proxy to OpenClaw gateway..."

    # Check if tailscale serve is available on this tailnet
    local serve_check
    serve_check=$(timeout 5 sudo tailscale serve status 2>&1 || true)
    if echo "${serve_check}" | grep -qi "not enabled"; then
        log_warn "Tailscale Serve is not enabled on your tailnet."
        local enable_url
        enable_url=$(echo "${serve_check}" | grep -o 'https://[^ ]*' | head -1 || echo "")
        if [[ -n "${enable_url}" ]]; then
            log_info "Enable it at: ${enable_url}"
        fi
        log_info "After enabling, run: sudo tailscale serve --bg http://127.0.0.1:18789"
    else
        # Try to configure the proxy
        local serve_ok=false
        if timeout 10 sudo tailscale serve --bg --https 443 http://127.0.0.1:18789 >> "${CLAWSPARK_LOG}" 2>&1; then
            serve_ok=true
        elif timeout 10 sudo tailscale serve --bg http://127.0.0.1:18789 >> "${CLAWSPARK_LOG}" 2>&1; then
            serve_ok=true
        fi

        if [[ "${serve_ok}" == "true" ]]; then
            log_success "Tailscale serve configured (HTTPS -> localhost:18789)."
        else
            log_warn "tailscale serve could not be configured automatically."
            log_info "You can set it up manually: sudo tailscale serve --bg http://127.0.0.1:18789"
        fi
    fi

    # Save the URL for the final install message
    local ts_url="https://${ts_fqdn}"
    echo "${ts_url}" > "${CLAWSPARK_DIR}/tailscale.url"

    # ── Print access information ─────────────────────────────────────────────
    printf '\n'
    print_box \
        "${BOLD}Tailscale Remote Access${RESET}" \
        "" \
        "OpenClaw gateway:" \
        "  ${ts_url}" \
        "" \
        "To also expose the ClawMetry dashboard:" \
        "  tailscale serve --bg --https 8900 http://127.0.0.1:8900" \
        "" \
        "Access from any device on your Tailnet." \
        "Traffic is encrypted end-to-end via WireGuard."
    printf '\n'

    log_info "Access your AI assistant from any device on your Tailnet at ${ts_url}"
    log_success "Tailscale setup complete."
}
