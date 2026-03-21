#!/usr/bin/env bash
# lib/setup-voice.sh — Installs Whisper-based voice skills and selects
# the appropriate model size for the detected hardware.
set -euo pipefail

setup_voice() {
    log_info "Setting up voice capabilities..."
    hr

    # ── Pick Whisper model size based on platform ───────────────────────────
    local whisper_model="base"
    case "${HW_PLATFORM}" in
        dgx-spark)
            whisper_model="large-v3"
            ;;
        jetson)
            whisper_model="small"
            ;;
        rtx)
            if (( HW_GPU_VRAM_MB >= 24576 )); then
                whisper_model="medium"
            else
                whisper_model="base"
            fi
            ;;
        *)
            whisper_model="base"
            ;;
    esac

    log_info "Whisper model size: ${whisper_model} (for ${HW_PLATFORM})"

    # ── Install local-whisper skill (skip if already installed by skills step)
    local whisper_skill_dir="${HOME}/.openclaw/workspace/skills/local-whisper"
    if [[ -d "${whisper_skill_dir}" ]]; then
        log_info "local-whisper already installed (from skills step)."
    else
        printf '  %s→%s Installing local-whisper skill ... ' "${CYAN}" "${RESET}"
        if npx --yes clawhub@latest install --force local-whisper >> "${CLAWSPARK_LOG}" 2>&1; then
            printf '%s✓%s\n' "${GREEN}" "${RESET}"
        else
            printf '%s✗%s\n' "${RED}" "${RESET}"
            log_warn "local-whisper installation failed — voice features may not work."
        fi
    fi

    # ── Install WhatsApp voice integration if applicable ────────────────────
    local messaging="${FLAG_MESSAGING:-${MESSAGING_CHOICE:-skip}}"
    messaging=$(to_lower "${messaging}")
    if [[ "${messaging}" == "whatsapp" || "${messaging}" == "both" ]]; then
        local voice_skill_dir="${HOME}/.openclaw/workspace/skills/whatsapp-voice-chat-integration-open-source"
        if [[ -d "${voice_skill_dir}" ]]; then
            log_info "whatsapp-voice-chat-integration already installed (from skills step)."
        else
            printf '  %s→%s Installing whatsapp-voice-chat-integration-open-source ... ' "${CYAN}" "${RESET}"
            if npx --yes clawhub@latest install --force whatsapp-voice-chat-integration-open-source >> "${CLAWSPARK_LOG}" 2>&1; then
                printf '%s✓%s\n' "${GREEN}" "${RESET}"
            else
                printf '%s✗%s\n' "${RED}" "${RESET}"
                log_warn "whatsapp-voice-chat-integration failed — voice notes may not work."
            fi
        fi
    fi

    # ── Configure Whisper model size ────────────────────────────────────────
    local whisper_config_dir="${HOME}/.openclaw/skills/local-whisper"
    mkdir -p "${whisper_config_dir}"

    # Detect compute device: CUDA (NVIDIA), Metal (macOS), or CPU fallback
    local whisper_device="cpu"
    local whisper_compute="int8"
    if check_command nvidia-smi && nvidia-smi &>/dev/null; then
        whisper_device="cuda"
        whisper_compute="float16"
    elif [[ "$(uname)" == "Darwin" ]]; then
        # macOS Apple Silicon uses Metal via CoreML/ANE acceleration
        whisper_device="auto"
        whisper_compute="int8"
    fi

    cat > "${whisper_config_dir}/config.json" <<WCEOF
{
  "model": "${whisper_model}",
  "language": "auto",
  "device": "${whisper_device}",
  "compute_type": "${whisper_compute}"
}
WCEOF
    log_info "Whisper config written (model=${whisper_model})."

    # ── Verification ────────────────────────────────────────────────────────
    # A full transcription test requires an audio file; we just verify the
    # config and skill presence.
    if [[ -f "${whisper_config_dir}/config.json" ]]; then
        log_success "Voice setup complete — Whisper ${whisper_model} configured."
    else
        log_warn "Whisper config file not found — voice may need manual setup."
    fi

    export WHISPER_MODEL="${whisper_model}"
}
