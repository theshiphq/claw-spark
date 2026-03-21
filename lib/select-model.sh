#!/usr/bin/env bash
# lib/select-model.sh — Recommends and lets the user pick an LLM based on hardware.
# Uses llmfit (https://github.com/AlexsJones/llmfit) for non-DGX-Spark platforms.
# Models are verified against the Ollama library before being shown.
# Exports: SELECTED_MODEL_ID, SELECTED_MODEL_NAME, SELECTED_MODEL_CTX
set -euo pipefail

select_model() {
    log_info "Selecting model for ${HW_PLATFORM}..."

    # ── If --model was passed on command line, use it directly ──────────────
    if [[ -n "${FLAG_MODEL:-}" ]]; then
        SELECTED_MODEL_ID="${FLAG_MODEL}"
        SELECTED_MODEL_NAME="${FLAG_MODEL}"
        SELECTED_MODEL_CTX=32768
        export SELECTED_MODEL_ID SELECTED_MODEL_NAME SELECTED_MODEL_CTX
        log_success "Model set via command line: ${SELECTED_MODEL_ID}"
        return 0
    fi

    # ── Select based on platform ───────────────────────────────────────────
    case "${HW_PLATFORM}" in
        dgx-spark)
            _select_model_curated_spark
            ;;
        mac|jetson|rtx|generic|*)
            # Try llmfit first, fall back to curated list
            _select_model_llmfit || _select_model_curated_fallback
            ;;
    esac

    SELECTED_MODEL_CTX=32768
    export SELECTED_MODEL_ID SELECTED_MODEL_NAME SELECTED_MODEL_CTX

    printf '\n'
    print_box \
        "${BOLD}Model Selected${RESET}" \
        "" \
        "Name    : ${CYAN}${SELECTED_MODEL_NAME}${RESET}" \
        "ID      : ${SELECTED_MODEL_ID}" \
        "Context : ${SELECTED_MODEL_CTX} tokens"

    log_success "Model selected: ${SELECTED_MODEL_NAME} (${SELECTED_MODEL_ID})"
}

# ── DGX Spark: curated list (tested on real hardware + llmfit verified) ───
_select_model_curated_spark() {
    # Top models for DGX Spark (128 GB unified memory, NVIDIA GB10).
    # Ranked by llmfit score, cross-checked against Ollama library.
    # tok/s estimates from llmfit; qwen3.5:35b-a3b measured at ~59 tok/s.
    local -a model_ids=(
        "qwen3.5:35b-a3b"
        "qwen3.5:122b-a10b"
        "qwen3-coder-next"
        "qwen3-next"
        "qwen3-coder:30b"
    )
    local -a model_names=(
        "Qwen 3.5 35B-A3B"
        "Qwen 3.5 122B-A10B"
        "Qwen3 Coder Next 80B"
        "Qwen3 Next 80B-A3B"
        "Qwen3 Coder 30B-A3B"
    )
    local -a model_labels=(
        "qwen3.5:35b-a3b (default) -- 18GB, ~59 tok/s, proven on Spark"
        "qwen3.5:122b-a10b -- 33GB, ~45 tok/s, top llmfit score (95.5)"
        "qwen3-coder-next -- 52GB, ~109 tok/s est., coding/agentic"
        "qwen3-next -- 50GB, ~59 tok/s est., chat/instruct"
        "qwen3-coder:30b -- 19GB, ~58 tok/s est., coding lightweight"
        "Let me pick my own model"
    )
    local default_idx=0

    _present_model_choices model_ids model_names model_labels "${default_idx}"
}

# ── llmfit-powered selection for all other platforms ──────────────────────
_select_model_llmfit() {
    _ensure_llmfit || return 1

    printf '  %s->%s Analyzing hardware with llmfit... ' "${CYAN}" "${RESET}" >/dev/tty
    local json
    json=$(llmfit recommend --json -n 20 --min-fit good 2>>"${CLAWSPARK_LOG}") || {
        printf '%sskipped%s\n' "${YELLOW}" "${RESET}" >/dev/tty
        log_warn "llmfit recommend failed -- falling back to curated list."
        return 1
    }
    printf '%sdone%s\n' "${GREEN}" "${RESET}" >/dev/tty

    # Parse llmfit JSON and map to Ollama model IDs (returns up to 10 candidates)
    local parsed
    parsed=$(_parse_llmfit_to_ollama "${json}" 2>>"${CLAWSPARK_LOG}") || return 1

    if [[ -z "${parsed}" ]]; then
        log_warn "No llmfit models mapped to Ollama -- falling back to curated list."
        return 1
    fi

    # Verify each candidate exists on Ollama library, keep top 5
    printf '  %s->%s Verifying models on Ollama... ' "${CYAN}" "${RESET}" >/dev/tty
    local -a model_ids=()
    local -a model_names=()
    local -a model_labels=()

    while IFS='|' read -r oid name label; do
        if _check_ollama_model "${oid}"; then
            model_ids+=("${oid}")
            model_names+=("${name}")
            model_labels+=("${label}")
        fi
        [[ ${#model_ids[@]} -ge 5 ]] && break
    done <<< "${parsed}"
    printf '%s%d verified%s\n' "${GREEN}" "${#model_ids[@]}" "${RESET}" >/dev/tty

    if [[ ${#model_ids[@]} -eq 0 ]]; then
        log_warn "No llmfit models found on Ollama -- falling back to curated list."
        return 1
    fi

    # Add custom option
    model_labels+=("Let me pick my own model")
    local default_idx=0

    log_info "Found ${#model_ids[@]} compatible model(s) on Ollama for your hardware."
    _present_model_choices model_ids model_names model_labels "${default_idx}"
}

# ── Check if a model exists on the Ollama library ─────────────────────────
_check_ollama_model() {
    local model_id="$1"

    # Try local first (instant if already pulled)
    ollama show "${model_id}" &>/dev/null 2>&1 && return 0

    # Check Ollama library website (model page exists = model available)
    local base="${model_id%%:*}"
    curl -sf --max-time 5 "https://ollama.com/library/${base}" -o /dev/null 2>/dev/null
}

# ── Curated fallback for non-Spark platforms ──────────────────────────────
_select_model_curated_fallback() {
    local -a model_ids=()
    local -a model_names=()
    local -a model_labels=()
    local default_idx=0

    case "${HW_PLATFORM}" in
        jetson)
            model_ids=("nemotron-3-nano" "glm-4.7-flash")
            model_names=("Nemotron 3 Nano 30B" "GLM 4.7 Flash")
            model_labels=(
                "nemotron-3-nano (default) -- optimized for Jetson"
                "glm-4.7-flash -- compact & fast"
            )
            ;;
        mac)
            # Apple Silicon with unified memory -- model size depends on RAM
            local ram_gb=$(( ${HW_TOTAL_RAM_MB:-0} / 1024 ))
            if (( ram_gb >= 32 )); then
                model_ids=("qwen3.5:35b-a3b" "qwen3-coder:30b" "glm-4.7-flash")
                model_names=("Qwen 3.5 35B-A3B" "Qwen3 Coder 30B" "GLM 4.7 Flash")
                model_labels=(
                    "qwen3.5:35b-a3b (default) -- MoE, fits 32GB+ Mac"
                    "qwen3-coder:30b -- coding-focused MoE"
                    "glm-4.7-flash -- compact & fast"
                )
            elif (( ram_gb >= 16 )); then
                model_ids=("glm-4.7-flash" "qwen3:8b" "deepseek-v2")
                model_names=("GLM 4.7 Flash" "Qwen3 8B" "DeepSeek V2")
                model_labels=(
                    "glm-4.7-flash (default) -- good balance for 16GB"
                    "qwen3:8b -- lightweight 8B model"
                    "deepseek-v2 -- MoE, good coding"
                )
            else
                model_ids=("qwen3:8b" "glm-4.7-flash")
                model_names=("Qwen3 8B" "GLM 4.7 Flash")
                model_labels=(
                    "qwen3:8b (default) -- fits 8GB Mac"
                    "glm-4.7-flash -- compact"
                )
            fi
            ;;
        rtx)
            local vram_gb=$(( ${HW_GPU_VRAM_MB:-0} / 1024 ))
            if (( vram_gb >= 24 )); then
                # RTX 3090, 4090, A5000+
                model_ids=("qwen3.5:35b-a3b" "qwen3-coder:30b" "glm-4.7-flash")
                model_names=("Qwen 3.5 35B-A3B" "Qwen3 Coder 30B" "GLM 4.7 Flash")
                model_labels=(
                    "qwen3.5:35b-a3b (default) -- MoE, fits 24GB (~18GB model)"
                    "qwen3-coder:30b -- coding-focused MoE"
                    "glm-4.7-flash -- compact & fast"
                )
            elif (( vram_gb >= 16 )); then
                # RTX 3080 16GB, 4080, A4000
                model_ids=("glm-4.7-flash" "qwen3:14b" "qwen3:8b")
                model_names=("GLM 4.7 Flash" "Qwen3 14B" "Qwen3 8B")
                model_labels=(
                    "glm-4.7-flash (default) -- fits 16GB"
                    "qwen3:14b -- mid-size model"
                    "qwen3:8b -- lightweight"
                )
            elif (( vram_gb >= 12 )); then
                # RTX 3060 12GB
                model_ids=("qwen3:14b" "qwen3:8b" "glm-4.7-flash")
                model_names=("Qwen3 14B" "Qwen3 8B" "GLM 4.7 Flash")
                model_labels=(
                    "qwen3:14b (default) -- fits 12GB"
                    "qwen3:8b -- smaller, faster"
                    "glm-4.7-flash -- compact"
                )
            else
                # RTX 3070/4060/4060 Ti (8GB), RTX 2060 (6GB)
                model_ids=("qwen3:8b" "phi4-mini")
                model_names=("Qwen3 8B" "Phi4 Mini")
                model_labels=(
                    "qwen3:8b (default) -- fits 8GB"
                    "phi4-mini -- very compact"
                )
            fi
            ;;
        *)
            model_ids=("glm-4.7-flash" "qwen3:8b")
            model_names=("GLM 4.7 Flash" "Qwen3 8B")
            model_labels=(
                "glm-4.7-flash (default)"
                "qwen3:8b -- lightweight"
            )
            ;;
    esac

    model_labels+=("Let me pick my own model")
    _present_model_choices model_ids model_names model_labels "${default_idx}"
}

# ── Shared: present choices and set SELECTED_MODEL_ID/NAME ────────────────
# Uses array names (Bash 3.2 compatible: no nameref)
_present_model_choices() {
    local _ids_name="$1"
    local _names_name="$2"
    local _labels_name="$3"
    local _default=$4
    local _labels_len
    eval "_labels_len=\${#${_labels_name}[@]}"

    local choice
    choice=$(prompt_choice "Which model would you like to run?" "${_labels_name}" "${_default}")

    if [[ "${choice}" == "Let me pick my own model" ]]; then
        if [[ "${CLAWSPARK_DEFAULTS}" == "true" ]]; then
            eval "SELECTED_MODEL_ID=\${${_ids_name}[$_default]}"
            eval "SELECTED_MODEL_NAME=\${${_names_name}[$_default]}"
        else
            printf '\n  %sEnter the Ollama model ID (e.g. llama3.1:8b):%s ' "${BOLD}" "${RESET}" >/dev/tty
            local custom_id
            read -r custom_id </dev/tty || custom_id=""
            if [[ -z "${custom_id}" ]]; then
                log_warn "No model entered -- falling back to default."
                eval "SELECTED_MODEL_ID=\${${_ids_name}[$_default]}"
                eval "SELECTED_MODEL_NAME=\${${_names_name}[$_default]}"
            else
                SELECTED_MODEL_ID="${custom_id}"
                SELECTED_MODEL_NAME="${custom_id}"
            fi
        fi
    else
        local i found=false
        local labels_last=$(( _labels_len - 2 ))
        for i in $(seq 0 "${labels_last}"); do
            local label_val
            eval "label_val=\${${_labels_name}[$i]}"
            if [[ "${label_val}" == "${choice}" ]]; then
                eval "SELECTED_MODEL_ID=\${${_ids_name}[$i]}"
                eval "SELECTED_MODEL_NAME=\${${_names_name}[$i]}"
                found=true
                break
            fi
        done
        if [[ "${found}" != "true" ]]; then
            log_warn "Could not match selection -- using default model."
            eval "SELECTED_MODEL_ID=\${${_ids_name}[$_default]}"
            eval "SELECTED_MODEL_NAME=\${${_names_name}[$_default]}"
        fi
    fi
}

# ── Install llmfit if not present ─────────────────────────────────────────
_ensure_llmfit() {
    if command -v llmfit &>/dev/null; then
        return 0
    fi

    log_info "Installing llmfit for hardware-aware model selection..."
    printf '  %s->%s Installing llmfit ... ' "${CYAN}" "${RESET}" >/dev/tty

    if curl -fsSL https://llmfit.axjns.dev/install.sh | sh >> "${CLAWSPARK_LOG}" 2>&1; then
        hash -r 2>/dev/null || true
        if command -v llmfit &>/dev/null; then
            printf '%sOK%s\n' "${GREEN}" "${RESET}" >/dev/tty
            return 0
        fi
        # Check common install locations
        local p
        for p in "${HOME}/.local/bin" "${HOME}/bin" "${HOME}/.cargo/bin" "/usr/local/bin"; do
            if [[ -x "${p}/llmfit" ]]; then
                export PATH="${p}:${PATH}"
                printf '%sOK%s\n' "${GREEN}" "${RESET}" >/dev/tty
                return 0
            fi
        done
    fi

    printf '%sskipped%s\n' "${YELLOW}" "${RESET}" >/dev/tty
    log_warn "Could not install llmfit -- using curated model list."
    return 1
}

# ── Parse llmfit JSON and map to Ollama model IDs ─────────────────────────
# Returns up to 10 candidates as: ollama_id|display_name|label (one per line)
_parse_llmfit_to_ollama() {
    local json="$1"

    python3 -c "
import json, sys, re

# Map llmfit HF-style model names to Ollama model IDs.
# Each entry: (regex_pattern, ollama_template)
# Templates use {size} for parameter count extracted from the name/param field.
PATTERNS = [
    # Qwen3 Coder Next (must be before generic Qwen3 patterns)
    (r'(?i)qwen3-coder-next|qwen3.*coder.*next',  'qwen3-coder-next'),
    # Qwen3 Coder (30B-A3B is the main variant on Ollama)
    (r'(?i)qwen3.*coder.*30b',        'qwen3-coder:30b'),
    (r'(?i)qwen3.*coder.*480b',       'qwen3-coder:480b'),
    (r'(?i)qwen3.*coder',             'qwen3-coder:30b'),
    # Qwen3 Next (80B-A3B is the main variant on Ollama)
    (r'(?i)qwen3-next|qwen3.*next.*80b', 'qwen3-next'),
    # Qwen3.5 family (specific MoE variants first)
    (r'(?i)qwen.*3\.5.*35b.*a3b',     'qwen3.5:35b-a3b'),
    (r'(?i)qwen.*3\.5.*122b.*a10b',   'qwen3.5:122b-a10b'),
    (r'(?i)qwen.*3\.5.*122b',         'qwen3.5:122b'),
    (r'(?i)qwen.*3\.5.*(\d+)b',       'qwen3.5:{size}b'),
    # Generic Qwen3 (non-coder, non-next)
    (r'(?i)qwen.*?3[^.].*?(\d+)b',    'qwen3:{size}b'),
    # Qwen 2.x
    (r'(?i)qwen.*2\.5.*(\d+)b',       'qwen2.5:{size}b'),
    (r'(?i)qwen.*2.*(\d+)b',          'qwen2:{size}b'),
    # Llama family
    (r'(?i)llama.*3\.3.*(\d+)b',      'llama3.3:{size}b'),
    (r'(?i)llama.*3\.1.*(\d+)b',      'llama3.1:{size}b'),
    (r'(?i)llama.*3.*(\d+)b',         'llama3:{size}b'),
    # Microsoft Phi
    (r'(?i)phi.*4.*mini',             'phi4-mini'),
    (r'(?i)phi.*4.*(\d+)b',          'phi4:{size}b'),
    (r'(?i)phi.*3.*mini',            'phi3:mini'),
    (r'(?i)phi.*3.*(\d+)b',          'phi3:{size}b'),
    # Google Gemma
    (r'(?i)gemma.*3.*(\d+)b',        'gemma3:{size}b'),
    (r'(?i)gemma.*2.*(\d+)b',        'gemma2:{size}b'),
    # Mistral
    (r'(?i)codestral.*(\d+)b',       'codestral:{size}b'),
    (r'(?i)mistral.*nemo',           'mistral-nemo'),
    (r'(?i)mistral.*large.*(\d+)b',  'mistral-large:{size}b'),
    (r'(?i)mistral.*small.*(\d+)b',  'mistral-small:{size}b'),
    (r'(?i)mixtral.*(\d+)x(\d+)b',  'mixtral:{size2}x{size}b'),
    (r'(?i)mistral.*(\d+)b',        'mistral:{size}b'),
    # DeepSeek
    (r'(?i)deepseek.*r1.*(\d+)b',   'deepseek-r1:{size}b'),
    (r'(?i)deepseek.*v3',           'deepseek-v3'),
    (r'(?i)deepseek.*v2.*lite',     'deepseek-v2:lite'),
    (r'(?i)deepseek.*v2.*16b',      'deepseek-v2:16b'),
    (r'(?i)deepseek.*v2',           'deepseek-v2'),
    # NVIDIA
    (r'(?i)nemotron.*nano',          'nemotron-3-nano'),
    (r'(?i)nemotron.*mini.*(\d+)b',  'nemotron-mini:{size}b'),
    # GLM
    (r'(?i)glm.*4.*flash',           'glm-4.7-flash'),
    (r'(?i)glm.*4.*(\d+)b',          'glm4:{size}b'),
    # Cohere
    (r'(?i)command.*r.*plus.*(\d+)b','command-r-plus:{size}b'),
    (r'(?i)command.*r.*(\d+)b',      'command-r:{size}b'),
    # StarCoder / Code models
    (r'(?i)starcoder.*2.*(\d+)b',    'starcoder2:{size}b'),
    # Yi
    (r'(?i)yi.*1\.5.*(\d+)b',        'yi:1.5-{size}b'),
    (r'(?i)yi.*(\d+)b',              'yi:{size}b'),
]

def map_to_ollama(name, param_count):
    text = name + ' ' + param_count
    for pattern, template in PATTERNS:
        m = re.search(pattern, text)
        if m:
            groups = m.groups()
            result = template
            if '{size}' in result:
                size = groups[0] if groups else ''
                if not size:
                    pm = re.search(r'(\d+)', param_count)
                    size = pm.group(1) if pm else ''
                result = result.replace('{size}', size.lower())
            if '{size2}' in result and len(groups) >= 2:
                result = result.replace('{size2}', groups[1].lower())
            return result
    return None

data = json.loads(sys.argv[1])
models = data.get('models', [])
seen = set()
results = []

for m in models:
    ollama_id = map_to_ollama(m.get('name', ''), m.get('parameter_count', ''))
    if not ollama_id or ollama_id in seen:
        continue
    seen.add(ollama_id)

    score = m.get('score', 0)
    tps = m.get('estimated_tps', 0)
    fit = m.get('fit_level', 'Unknown')
    quant = m.get('best_quant', '')
    mem = m.get('memory_required_gb', 0)
    use_case = m.get('use_case', '')

    # Shorten use_case for label
    cat = ''
    uc = use_case.lower()
    if 'cod' in uc or 'agent' in uc:
        cat = ', coding'
    elif 'chat' in uc or 'instruct' in uc:
        cat = ', chat'

    default_tag = ' (recommended)' if not results else ''
    label = f'{ollama_id}{default_tag} -- {mem:.0f}GB, ~{tps:.0f} tok/s, {fit} fit{cat}'
    print(f'{ollama_id}|{ollama_id}|{label}')
    results.append(ollama_id)
    if len(results) >= 10:
        break
" "${json}"
}
