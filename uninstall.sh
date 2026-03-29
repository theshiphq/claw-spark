#!/usr/bin/env bash
# uninstall.sh — Clean removal of clawspark, OpenClaw, models, and configs.
set -euo pipefail

CLAWSPARK_DIR="${HOME}/.clawspark"

# ── Minimal color support ──────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
    CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; RESET=''
fi

log_info()    { printf '%s[INFO]%s %s\n' "${CYAN}" "${RESET}" "$*"; }
log_warn()    { printf '%s[WARN]%s %s\n' "${YELLOW}" "${RESET}" "$*" >&2; }
log_success() { printf '%s[OK]%s %s\n' "${GREEN}" "${RESET}" "$*"; }
log_error()   { printf '%s[ERROR]%s %s\n' "${RED}" "${RESET}" "$*" >&2; }

# ── Confirmation ────────────────────────────────────────────────────────────
confirmed=false
if [[ "${1:-}" == "--confirmed" ]]; then
    confirmed=true
fi

if ! ${confirmed}; then
    printf '\n%s%s clawspark uninstaller%s\n\n' "${BOLD}" "${RED}" "${RESET}"
    printf '  This will remove:\n'
    printf '    - OpenClaw (npm global package)\n'
    printf '    - OpenClaw configuration (~/.openclaw)\n'
    printf '    - clawspark data (~/.clawspark)\n'
    printf '    - clawspark CLI (/usr/local/bin/clawspark)\n'
    printf '    - Optionally: Ollama models\n'
    printf '    - Optionally: firewall rules\n\n'

    printf '  %sType YES to proceed:%s ' "${RED}" "${RESET}"
    read -r answer
    if [[ "${answer}" != "YES" ]]; then
        log_info "Uninstall cancelled."
        exit 0
    fi
fi

printf '\n'

# ── Step 1: Stop services ──────────────────────────────────────────────────
log_info "Stopping services..."

# Gateway
if [[ -f "${CLAWSPARK_DIR}/gateway.pid" ]]; then
    local_pid=$(cat "${CLAWSPARK_DIR}/gateway.pid" 2>/dev/null || echo "")
    if [[ -n "${local_pid}" ]] && kill -0 "${local_pid}" 2>/dev/null; then
        kill "${local_pid}" 2>/dev/null || true
        log_info "Gateway stopped (PID ${local_pid})."
    fi
fi

# Ollama (only our managed instance)
if [[ -f "${CLAWSPARK_DIR}/ollama.pid" ]]; then
    local_pid=$(cat "${CLAWSPARK_DIR}/ollama.pid" 2>/dev/null || echo "")
    if [[ -n "${local_pid}" ]] && kill -0 "${local_pid}" 2>/dev/null; then
        kill "${local_pid}" 2>/dev/null || true
        log_info "Ollama stopped (PID ${local_pid})."
    fi
fi

# If Ollama is managed by systemd, stop it too
if command -v systemctl &>/dev/null && systemctl is-active ollama &>/dev/null; then
    log_info "Stopping Ollama systemd service..."
    sudo systemctl stop ollama 2>/dev/null || true
fi

log_success "Services stopped."

# ── Step 2: Optionally remove Ollama models ────────────────────────────────
if command -v ollama &>/dev/null; then
    if ${confirmed}; then
        remove_models="n"
    else
        printf '\n  %sRemove all Ollama models? This frees disk space but re-download needed later.%s\n' "${YELLOW}" "${RESET}"
        printf '  %s[y/N]:%s ' "${BOLD}" "${RESET}"
        read -r remove_models
        remove_models=$(echo "${remove_models}" | tr '[:upper:]' '[:lower:]')
    fi

    if [[ "${remove_models}" =~ ^y ]]; then
        log_info "Removing Ollama models..."
        local_models=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}')
        for model in ${local_models}; do
            printf '  Removing %s ... ' "${model}"
            ollama rm "${model}" 2>/dev/null && printf '%sdone%s\n' "${GREEN}" "${RESET}" \
                || printf '%sfailed%s\n' "${YELLOW}" "${RESET}"
        done
        log_success "Models removed."
    else
        log_info "Keeping Ollama models."
    fi
fi

# ── Step 3: Uninstall OpenClaw ──────────────────────────────────────────────
if command -v openclaw &>/dev/null; then
    log_info "Uninstalling OpenClaw..."
    npm uninstall -g openclaw 2>/dev/null || true
    log_success "OpenClaw removed."
else
    log_info "OpenClaw not found — skipping."
fi

# ── Step 4: Remove configuration directories ───────────────────────────────
log_info "Removing configuration directories..."

if [[ -d "${HOME}/.openclaw" ]]; then
    rm -rf "${HOME}/.openclaw"
    log_info "Removed ~/.openclaw"
fi

if [[ -d "${CLAWSPARK_DIR}" ]]; then
    rm -rf "${CLAWSPARK_DIR}"
    log_info "Removed ~/.clawspark"
fi

# ── Step 5: Remove CLI ─────────────────────────────────────────────────────
if [[ -f /usr/local/bin/clawspark ]]; then
    log_info "Removing /usr/local/bin/clawspark..."
    sudo rm -f /usr/local/bin/clawspark 2>/dev/null || {
        log_warn "Could not remove /usr/local/bin/clawspark — you may need to delete it manually."
    }
    log_success "CLI removed."
fi

# ── Step 6: Revert firewall rules ──────────────────────────────────────────
if command -v ufw &>/dev/null; then
    if ${confirmed}; then
        revert_fw="n"
    else
        printf '\n  %sRevert firewall (UFW) rules added by clawspark?%s\n' "${YELLOW}" "${RESET}"
        printf '  %s[y/N]:%s ' "${BOLD}" "${RESET}"
        read -r revert_fw
        revert_fw=$(echo "${revert_fw}" | tr '[:upper:]' '[:lower:]')
    fi

    if [[ "${revert_fw}" =~ ^y ]]; then
        log_info "Reverting UFW rules..."
        sudo ufw default allow outgoing 2>/dev/null || true
        # Reset rules added for air-gap
        sudo ufw delete allow out to 10.0.0.0/8 2>/dev/null || true
        sudo ufw delete allow out to 172.16.0.0/12 2>/dev/null || true
        sudo ufw delete allow out to 192.168.0.0/16 2>/dev/null || true
        sudo ufw delete allow out to 127.0.0.0/8 2>/dev/null || true
        sudo ufw delete allow out 53 2>/dev/null || true
        log_success "Firewall rules reverted."
    else
        log_info "Keeping firewall rules as-is."
    fi
fi

# ── Done ────────────────────────────────────────────────────────────────────
printf '\n'
printf '  %s%sclawspark has been completely removed.%s\n' "${GREEN}" "${BOLD}" "${RESET}"
printf '  Ollama itself was NOT uninstalled (only models were optionally removed).\n'
printf '  To remove Ollama: sudo rm -f /usr/local/bin/ollama\n\n'
