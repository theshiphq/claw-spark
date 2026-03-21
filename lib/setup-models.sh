#!/usr/bin/env bash
# lib/setup-models.sh -- Multi-model configuration for OpenClaw.
# Configures vision and image generation model slots alongside the
# primary chat model that was already selected during install.
set -euo pipefail

setup_models() {
    log_info "Configuring multi-model support..."

    # The primary model is already set during install (SELECTED_MODEL_ID).
    # Now configure additional model slots: vision and image generation.

    # ── Vision model ──────────────────────────────────────────────────────
    # Check for vision-capable models already pulled in Ollama
    local vision_models=("qwen2.5vl" "qwen2.5-vl" "llava" "minicpm-v" "llama3.2-vision" "moondream")
    local found_vision=""

    for vm in "${vision_models[@]}"; do
        if ollama list 2>/dev/null | grep -qi "${vm}"; then
            found_vision="${vm}"
            break
        fi
    done

    if [[ -n "${found_vision}" ]]; then
        # Get the full model tag from ollama list output
        local full_tag
        full_tag=$(ollama list 2>/dev/null | grep -i "${found_vision}" | head -1 | awk '{print $1}')
        log_success "Found vision model: ${full_tag}"
        openclaw config set agents.defaults.imageModel "ollama/${full_tag}" >> "${CLAWSPARK_LOG}" 2>&1 || true
    else
        # No vision model found -- decide whether to auto-pull based on VRAM
        local vram_gb=$(( ${HW_GPU_VRAM_MB:-0} / 1024 ))
        local skip_vision=false

        # RTX with <=12GB VRAM: pulling a 5GB vision model alongside the chat
        # model will cause OOM when both are loaded simultaneously
        if [[ "${HW_PLATFORM:-}" == "rtx" ]] && (( vram_gb > 0 && vram_gb <= 12 )); then
            skip_vision=true
            log_info "Skipping vision model auto-pull (${vram_gb}GB VRAM -- dual-model loading would OOM)."
            log_info "Add one later when needed: ollama pull moondream (1.5GB, fits alongside chat model)"
        fi

        if [[ "${skip_vision}" != "true" ]]; then
            local vision_choice="qwen2.5vl:7b"
            log_info "No vision model found. Pulling ${vision_choice} for image analysis (~5GB)..."
            (ollama pull "${vision_choice}") >> "${CLAWSPARK_LOG}" 2>&1 &
            spinner $! "Pulling ${vision_choice}..."
            # Wait a moment for Ollama to index the model, then check with retries
            local _vision_ok=false
            local _retry
            for _retry in 1 2 3; do
                if ollama list 2>/dev/null | grep -qi "qwen2.5vl"; then
                    _vision_ok=true
                    break
                fi
                sleep 2
            done
            if [[ "${_vision_ok}" == "true" ]]; then
                found_vision="qwen2.5vl"
                openclaw config set agents.defaults.imageModel "ollama/${vision_choice}" >> "${CLAWSPARK_LOG}" 2>&1 || true
                log_success "Vision model configured: ollama/${vision_choice}"
            else
                log_warn "Vision model pull failed. You can add one later: ollama pull qwen2.5vl:7b"
            fi
        fi
    fi

    # ── Register vision model with explicit input modality ─────────────────
    # OpenClaw discovers Ollama models via /v1/models which doesn't report
    # vision capability. We must explicitly register the model with
    # input: ["text", "image"] so the image tool works.
    local config_file="${HOME}/.openclaw/openclaw.json"
    if [[ -n "${found_vision}" && -f "${config_file}" ]]; then
        local vision_model_id="${found_vision}"
        # Get the full tag
        local vision_full_tag
        vision_full_tag=$(ollama list 2>/dev/null | grep -i "${vision_model_id}" | head -1 | awk '{print $1}')
        if [[ -n "${vision_full_tag}" ]]; then
            python3 -c "
import json, sys
path = sys.argv[1]
model_id = sys.argv[2]
with open(path) as f:
    cfg = json.load(f)
cfg.setdefault('models', {}).setdefault('providers', {}).setdefault('ollama', {})
cfg['models']['providers']['ollama'].setdefault('baseUrl', 'http://127.0.0.1:11434/v1')
# Use openai-completions api -- Ollama's /v1 endpoint is OpenAI-compatible
# and the built-in openai-completions provider is always registered,
# unlike the dynamic 'ollama' api which is missing from the vision code path.
cfg['models']['providers']['ollama']['api'] = 'openai-completions'
cfg['models']['providers']['ollama']['models'] = [
    {
        'id': model_id,
        'name': model_id.replace(':', ' ').title(),
        'api': 'openai-completions',
        'input': ['text', 'image'],
        'contextWindow': 32768,
        'maxTokens': 8192
    }
]
with open(path, 'w') as f:
    json.dump(cfg, f, indent=2)
print('ok')
" "${config_file}" "${vision_full_tag}" 2>> "${CLAWSPARK_LOG}" || {
                log_warn "Could not register vision model modality."
            }
            log_success "Vision model registered with image input capability."
        fi
    fi

    # ── Image generation model ────────────────────────────────────────────
    # Image generation (text-to-image) is optional and more complex.
    # It typically requires ComfyUI, Stable Diffusion, or an external API.
    # For now, log a message about how to enable it later.
    log_info "Image generation: not configured (optional)."
    log_info "  To enable later, set up ComfyUI or a text-to-image API and run:"
    log_info "  openclaw config set agents.defaults.imageGenerationModel <provider>/<model>"

    log_success "Model configuration complete."
}
