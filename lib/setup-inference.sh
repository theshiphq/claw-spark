#!/usr/bin/env bash
# lib/setup-inference.sh — Installs Ollama, pulls the chosen model, and
# waits for the inference API to become ready.
# Exports: INFERENCE_API_URL
set -euo pipefail

setup_inference() {
    log_info "Setting up inference engine (Ollama)..."
    hr

    # ── Jetson: set CUDA library path so Ollama can find GPU ─────────────────
    if [[ "${HW_PLATFORM:-}" == "jetson" ]] && [[ -d "/usr/local/cuda/lib64" ]]; then
        if [[ "${LD_LIBRARY_PATH:-}" != */usr/local/cuda/lib64* ]]; then
            export LD_LIBRARY_PATH="/usr/local/cuda/lib64:/usr/lib/aarch64-linux-gnu/tegra:${LD_LIBRARY_PATH:-}"
            log_info "Set LD_LIBRARY_PATH for Jetson CUDA: ${LD_LIBRARY_PATH}"
        fi
    fi

    # ── Install Ollama if missing ───────────────────────────────────────────
    if ! check_command ollama; then
        log_info "Ollama not found — installing..."
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS: check for Ollama.app first, then try Homebrew
            if [[ -d "/Applications/Ollama.app" ]]; then
                log_info "Ollama.app found but not on PATH. Adding..."
                export PATH="/Applications/Ollama.app/Contents/Resources:${PATH}"
            elif check_command brew; then
                log_info "Installing Ollama via Homebrew..."
                (brew install ollama) >> "${CLAWSPARK_LOG}" 2>&1 &
                spinner $! "Installing Ollama..."
            else
                log_info "Installing Ollama via install script..."
                curl -fsSL https://ollama.com/install.sh | sh >> "${CLAWSPARK_LOG}" 2>&1 || {
                    log_warn "Ollama install script returned an error."
                }
            fi
        else
            # Linux: use the official install script
            log_info "Installing via official script (this needs sudo)..."
            if curl -fsSL https://ollama.com/install.sh | sh >> "${CLAWSPARK_LOG}" 2>&1; then
                log_success "Ollama installed."
            else
                log_warn "Ollama install script returned an error."
            fi
        fi
        # Refresh PATH and check
        hash -r 2>/dev/null || true
        if ! check_command ollama; then
            log_error "Ollama installation failed. Check ${CLAWSPARK_LOG} for details."
            log_info "Install manually: https://ollama.com/download"
            return 1
        fi
    else
        log_success "Ollama is already installed."
    fi

    # ── Start Ollama service ────────────────────────────────────────────────
    if ! _ollama_is_running; then
        log_info "Starting Ollama service..."
        if [[ "$(uname)" == "Darwin" ]] && [[ -d "/Applications/Ollama.app" ]]; then
            # macOS: launch the Ollama app (it runs as a menubar service)
            open -a Ollama 2>/dev/null || true
            log_info "Launched Ollama.app."
        elif check_command systemctl && systemctl is-enabled ollama &>/dev/null; then
            sudo systemctl start ollama >> "${CLAWSPARK_LOG}" 2>&1 || true
        elif check_command snap && snap list ollama &>/dev/null 2>&1; then
            # DGX Spark / some Linux: Ollama installed as snap
            log_info "Ollama is a snap package -- starting via snap."
            sudo snap start ollama 2>> "${CLAWSPARK_LOG}" || true
        else
            # Start as a background process
            nohup ollama serve >> "${CLAWSPARK_DIR}/ollama.log" 2>&1 &
            local serve_pid=$!
            echo "${serve_pid}" > "${CLAWSPARK_DIR}/ollama.pid"
            log_info "Ollama serve started (PID ${serve_pid})."
        fi

        # Wait for the service to be ready
        _wait_for_ollama 30
    else
        log_success "Ollama is already running."
    fi

    # ── Pull the selected model ─────────────────────────────────────────────
    log_info "Pulling model: ${SELECTED_MODEL_ID} (this may take a while)..."
    if ollama list 2>/dev/null | grep -qF "${SELECTED_MODEL_ID}"; then
        log_success "Model ${SELECTED_MODEL_ID} is already available locally."
    else
        if ! ollama pull "${SELECTED_MODEL_ID}" 2>&1 | tee -a "${CLAWSPARK_LOG}"; then
            log_error "Failed to pull model ${SELECTED_MODEL_ID}."
            return 1
        fi
        log_success "Model ${SELECTED_MODEL_ID} downloaded."
    fi

    # ── Verify model is listed ──────────────────────────────────────────────
    if ! ollama list 2>/dev/null | grep -qF "${SELECTED_MODEL_ID}"; then
        log_error "Model ${SELECTED_MODEL_ID} not found in ollama list after pull."
        return 1
    fi

    # ── Set API URL ─────────────────────────────────────────────────────────
    INFERENCE_API_URL="http://127.0.0.1:11434/v1"
    export INFERENCE_API_URL

    log_success "Inference engine ready at ${INFERENCE_API_URL}"
}

# ── Internal helpers ────────────────────────────────────────────────────────

_ollama_is_running() {
    curl -sf http://127.0.0.1:11434/ &>/dev/null
}

_wait_for_ollama() {
    local max_attempts="${1:-30}"
    local attempt=0
    while (( attempt < max_attempts )); do
        if _ollama_is_running; then
            log_success "Ollama API is responsive."
            return 0
        fi
        attempt=$(( attempt + 1 ))
        sleep 1
    done
    log_error "Ollama did not become ready after ${max_attempts}s."
    return 1
}
