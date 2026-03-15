#!/usr/bin/env bash
# lib/setup-dashboard.sh -- Installs ClawMetry observability dashboard for OpenClaw.
# Provides metrics, logs, and health monitoring via a local web UI.
set -euo pipefail

setup_dashboard() {
    log_info "Setting up ClawMetry observability dashboard..."
    hr

    # ── Check dependencies ───────────────────────────────────────────────────
    if ! check_command python3; then
        log_warn "python3 not found -- skipping dashboard."
        return 0
    fi

    # ── Install ClawMetry ────────────────────────────────────────────────────
    local install_ok=false

    log_info "Installing ClawMetry via pip..."
    if _pip_install clawmetry; then
        install_ok=true
        log_success "ClawMetry installed via pip."
    else
        log_warn "pip install clawmetry failed -- falling back to git clone."

        # ── Fallback: clone from GitHub ──────────────────────────────
        local clone_dir="${CLAWSPARK_DIR}/clawmetry"
        if [[ -d "${clone_dir}" ]]; then
            log_info "Existing clone found at ${clone_dir} -- pulling latest..."
            (cd "${clone_dir}" && git pull) >> "${CLAWSPARK_LOG}" 2>&1 || true
        else
            log_info "Cloning ClawMetry from GitHub..."
            (git clone https://github.com/vivekchand/clawmetry.git "${clone_dir}") \
                >> "${CLAWSPARK_LOG}" 2>&1 &
            spinner $! "Cloning clawmetry..."
        fi

        if [[ -d "${clone_dir}" ]]; then
            log_info "Installing Flask dependency..."
            if _pip_install flask; then
                install_ok=true
                log_success "ClawMetry installed from source."
            else
                log_warn "Flask install failed -- dashboard may not work."
            fi
        else
            log_warn "Failed to clone ClawMetry -- skipping dashboard."
            return 0
        fi
    fi

    if [[ "${install_ok}" != "true" ]]; then
        log_warn "ClawMetry installation incomplete -- skipping dashboard."
        return 0
    fi

    # ── Configure ClawMetry workspace ────────────────────────────────────────
    local openclaw_dir="${HOME}/.openclaw"
    local clawmetry_config_dir="${CLAWSPARK_DIR}/clawmetry-config"
    mkdir -p "${clawmetry_config_dir}"

    cat > "${clawmetry_config_dir}/config.json" <<CMEOF
{
  "workspace": "${openclaw_dir}",
  "host": "127.0.0.1",
  "port": 8900,
  "log_file": "${CLAWSPARK_DIR}/dashboard.log"
}
CMEOF
    log_info "ClawMetry configured to use OpenClaw workspace at ${openclaw_dir}"

    # ── Start ClawMetry as a background service ──────────────────────────────
    _start_dashboard

    # ── Verify dashboard is accessible ───────────────────────────────────────
    local retries=5
    local dashboard_up=false
    while (( retries > 0 )); do
        if curl -sf --max-time 2 http://127.0.0.1:8900 &>/dev/null; then
            dashboard_up=true
            break
        fi
        sleep 1
        retries=$(( retries - 1 ))
    done

    if [[ "${dashboard_up}" == "true" ]]; then
        log_success "ClawMetry dashboard is running at http://127.0.0.1:8900"
    else
        log_warn "ClawMetry dashboard did not respond -- it may still be starting."
        log_info "Check logs at ${CLAWSPARK_DIR}/dashboard.log"
    fi

    # ── Print dashboard URLs ─────────────────────────────────────────────────
    printf '\n'
    print_box \
        "${BOLD}Dashboard URLs${RESET}" \
        "" \
        "ClawMetry (observability):  http://127.0.0.1:8900" \
        "OpenClaw Control UI:        http://127.0.0.1:18789/__openclaw__/canvas/" \
        "" \
        "The Control UI is built into the OpenClaw gateway" \
        "and requires no additional setup."
    printf '\n'

    log_success "Dashboard setup complete."
}

# ── Internal helpers ─────────────────────────────────────────────────────────

# pip install that handles PEP 668 (externally managed Python on Ubuntu 23.04+)
_pip_install() {
    local pkg="$1"
    # Try normal pip first
    if pip3 install "${pkg}" >> "${CLAWSPARK_LOG}" 2>&1; then
        return 0
    fi
    # Try --user
    if pip3 install --user "${pkg}" >> "${CLAWSPARK_LOG}" 2>&1; then
        return 0
    fi
    # Try --break-system-packages (PEP 668 workaround for managed Python)
    if pip3 install --break-system-packages "${pkg}" >> "${CLAWSPARK_LOG}" 2>&1; then
        return 0
    fi
    # Try python3 -m pip as last resort
    if python3 -m pip install --break-system-packages "${pkg}" >> "${CLAWSPARK_LOG}" 2>&1; then
        return 0
    fi
    return 1
}

_start_dashboard() {
    local dashboard_log="${CLAWSPARK_DIR}/dashboard.log"
    local dashboard_pid_file="${CLAWSPARK_DIR}/dashboard.pid"

    # Kill existing dashboard if running
    if [[ -f "${dashboard_pid_file}" ]]; then
        local old_pid
        old_pid=$(cat "${dashboard_pid_file}")
        if kill -0 "${old_pid}" 2>/dev/null; then
            log_info "Stopping existing dashboard (PID ${old_pid})..."
            kill "${old_pid}" 2>/dev/null || true
            sleep 1
        fi
    fi

    log_info "Starting ClawMetry dashboard..."
    nohup python3 -m clawmetry --port 8900 --host 127.0.0.1 > "${dashboard_log}" 2>&1 &
    local dash_pid=$!
    echo "${dash_pid}" > "${dashboard_pid_file}"

    sleep 2
    if kill -0 "${dash_pid}" 2>/dev/null; then
        log_success "ClawMetry running (PID ${dash_pid}). Logs: ${dashboard_log}"
    else
        log_warn "ClawMetry process exited unexpectedly. Check ${dashboard_log}."
    fi
}
