#!/usr/bin/env bash
# lib/setup-browser.sh -- Browser automation setup for OpenClaw.
# Detects or installs Chromium/Chrome and configures the browser tool
# in managed headless mode.
set -euo pipefail

setup_browser() {
    log_info "Setting up browser automation..."

    local browser_bin=""
    if check_command chromium-browser; then
        browser_bin="chromium-browser"
    elif check_command chromium; then
        browser_bin="chromium"
    elif check_command google-chrome; then
        browser_bin="google-chrome"
    elif check_command google-chrome-stable; then
        browser_bin="google-chrome-stable"
    fi

    # macOS: check common app bundle paths if no CLI binary found
    if [[ -z "${browser_bin}" && "$(uname)" == "Darwin" ]]; then
        local -a mac_browsers=(
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
            "/Applications/Chromium.app/Contents/MacOS/Chromium"
            "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
            "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
        )
        for candidate in "${mac_browsers[@]}"; do
            if [[ -x "${candidate}" ]]; then
                browser_bin="${candidate}"
                break
            fi
        done
    fi

    if [[ -n "${browser_bin}" ]]; then
        log_success "Browser found: ${browser_bin}"
    else
        log_info "No browser found. Installing Chromium for browser automation..."
        if check_command apt-get; then
            # Ubuntu 20.04+ and Jetson: apt chromium-browser installs a snap stub
            # that doesn't work headless or under systemd. Prefer google-chrome.
            local _snap_chromium=false
            if command -v snap &>/dev/null && snap list chromium &>/dev/null 2>&1; then
                _snap_chromium=true
            fi
            if [[ "${_snap_chromium}" == "true" ]] || dpkg -l chromium-browser 2>/dev/null | grep -q "^ii.*snap"; then
                log_warn "Snap Chromium detected (broken for headless/systemd). Trying Google Chrome..."
            fi
            # Try Google Chrome first (always works headless)
            if ! check_command google-chrome-stable && ! check_command google-chrome; then
                (sudo apt-get install -y chromium-browser 2>/dev/null || sudo apt-get install -y chromium) >> "${CLAWSPARK_LOG}" 2>&1 &
                spinner $! "Installing Chromium..."
            fi
            if check_command google-chrome-stable; then
                browser_bin="google-chrome-stable"
            elif check_command google-chrome; then
                browser_bin="google-chrome"
            elif check_command chromium-browser; then
                browser_bin="chromium-browser"
            elif check_command chromium; then
                browser_bin="chromium"
            fi
            if [[ -n "${browser_bin}" ]]; then
                log_success "Browser installed: ${browser_bin}"
            else
                log_warn "Browser installation failed. Browser tool will not be available."
                return 0
            fi
        elif check_command brew; then
            log_info "Installing Chromium via Homebrew..."
            (brew install --cask chromium) >> "${CLAWSPARK_LOG}" 2>&1 &
            spinner $! "Installing Chromium..."
            if check_command chromium || [[ -d "/Applications/Chromium.app" ]]; then
                browser_bin=$(command -v chromium 2>/dev/null || echo "/Applications/Chromium.app/Contents/MacOS/Chromium")
                log_success "Chromium installed: ${browser_bin}"
            else
                log_warn "Chromium installation failed. Browser tool will not be available."
                return 0
            fi
        else
            log_warn "No package manager found. Install Chromium manually to enable browser automation."
            return 0
        fi
    fi

    # Browser config: OpenClaw manages browser via agents.defaults.sandbox.browser
    # The browser binary path is stored in clawspark's own config for the CLI
    local cs_config="${CLAWSPARK_DIR}/config.json"
    python3 -c "
import json, sys, os

path = sys.argv[1]
browser_bin = sys.argv[2]

cfg = {}
if os.path.exists(path):
    with open(path, 'r') as f:
        cfg = json.load(f)

cfg['browser'] = {
    'executablePath': browser_bin,
    'headless': True
}

with open(path, 'w') as f:
    json.dump(cfg, f, indent=2)
print('ok')
" "${cs_config}" "${browser_bin}" 2>> "${CLAWSPARK_LOG}" || {
        log_warn "Could not save browser config"
    }

    # Clean up any invalid root-level browser keys from openclaw.json
    local oc_config="${HOME}/.openclaw/openclaw.json"
    if [[ -f "${oc_config}" ]]; then
        python3 -c "
import json, sys
path = sys.argv[1]
with open(path, 'r') as f:
    cfg = json.load(f)
changed = False
if 'browser' in cfg:
    if 'mode' in cfg['browser']:
        del cfg['browser']['mode']
        changed = True
    if not cfg['browser']:
        del cfg['browser']
        changed = True
if changed:
    with open(path, 'w') as f:
        json.dump(cfg, f, indent=2)
print('ok')
" "${oc_config}" 2>> "${CLAWSPARK_LOG}" || true
    fi

    log_success "Browser configured: ${browser_bin} (headless)."
}
