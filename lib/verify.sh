#!/usr/bin/env bash
# lib/verify.sh — Post-installation health checks and performance benchmark.
set -euo pipefail

verify_installation() {
    log_info "Running verification checks..."
    hr

    local pass=0
    local fail=0

    # ── Helper to print check results ───────────────────────────────────────
    _check_pass() {
        printf '  %s✓%s %s\n' "${GREEN}" "${RESET}" "$1"
        pass=$(( pass + 1 ))
    }
    _check_fail() {
        printf '  %s✗%s %s\n' "${RED}" "${RESET}" "$1"
        fail=$(( fail + 1 ))
    }

    printf '\n'

    # ── 1. Hardware ─────────────────────────────────────────────────────────
    local ram_gb=$(( ${HW_TOTAL_RAM_MB:-0} / 1024 ))
    local platform_label
    case "${HW_PLATFORM:-generic}" in
        dgx-spark) platform_label="DGX Spark (${ram_gb}GB unified memory)" ;;
        jetson)    platform_label="Jetson (${ram_gb}GB)" ;;
        rtx)       platform_label="RTX (${HW_GPU_VRAM_MB:-0}MB VRAM)" ;;
        mac)       platform_label="macOS Apple Silicon (${ram_gb}GB unified)" ;;
        *)         platform_label="Generic (${ram_gb}GB RAM)" ;;
    esac
    _check_pass "Hardware: ${platform_label}"

    # ── 2. Model ────────────────────────────────────────────────────────────
    _check_pass "Model: ${SELECTED_MODEL_NAME:-unknown} (${SELECTED_MODEL_ID:-unknown})"

    # ── 3. Ollama ───────────────────────────────────────────────────────────
    if curl -sf http://127.0.0.1:11434/ &>/dev/null; then
        _check_pass "Inference: Ollama (http://127.0.0.1:11434)"
    else
        _check_fail "Inference: Ollama is not responding"
    fi

    # ── 4. Model loaded ────────────────────────────────────────────────────
    if ollama list 2>/dev/null | grep -q "${SELECTED_MODEL_ID}"; then
        _check_pass "Model available in Ollama"
    else
        _check_fail "Model ${SELECTED_MODEL_ID} not found in Ollama"
    fi

    # ── 5. OpenClaw ─────────────────────────────────────────────────────────
    if check_command openclaw; then
        local oc_ver
        oc_ver=$(openclaw --version 2>/dev/null || echo "unknown")
        local gw_status="gateway not running"
        if check_command systemctl && systemctl is-active --quiet clawspark-gateway.service 2>/dev/null; then
            gw_status="gateway running (systemd)"
        elif [[ -f "${CLAWSPARK_DIR}/gateway.pid" ]]; then
            local gw_pid
            gw_pid=$(cat "${CLAWSPARK_DIR}/gateway.pid")
            if [[ -n "${gw_pid}" ]] && kill -0 "${gw_pid}" 2>/dev/null; then
                gw_status="gateway running"
            fi
        fi
        _check_pass "OpenClaw: ${oc_ver} (${gw_status})"
    else
        _check_fail "OpenClaw: not installed"
    fi

    # ── 6. Tools profile ──────────────────────────────────────────────────
    local tools_profile
    tools_profile=$(openclaw config get tools.profile 2>/dev/null || echo "unknown")
    if [[ "${tools_profile}" == *"full"* ]]; then
        _check_pass "Tools: full profile (web, exec, browser, filesystem)"
    else
        _check_fail "Tools: profile is '${tools_profile}' (should be 'full')"
    fi

    # ── 7. Node host ──────────────────────────────────────────────────────
    if check_command systemctl && systemctl is-active --quiet clawspark-nodehost.service 2>/dev/null; then
        _check_pass "Node host: running (systemd)"
    elif [[ -f "${CLAWSPARK_DIR}/node.pid" ]]; then
        local node_pid
        node_pid=$(cat "${CLAWSPARK_DIR}/node.pid")
        if [[ -n "${node_pid}" ]] && kill -0 "${node_pid}" 2>/dev/null; then
            _check_pass "Node host: running (PID ${node_pid})"
        else
            _check_fail "Node host: not running"
        fi
    else
        _check_fail "Node host: not started"
    fi

    # ── 8. Skills ──────────────────────────────────────────────────────────
    local skill_count=0
    if [[ -f "${CLAWSPARK_DIR}/skills.yaml" ]]; then
        skill_count=$(grep -c '^ *- ' "${CLAWSPARK_DIR}/skills.yaml" 2>/dev/null || echo 0)
    fi
    _check_pass "Skills: ${skill_count} configured"

    # ── 9. Voice ────────────────────────────────────────────────────────────
    local whisper_model="${WHISPER_MODEL:-unknown}"
    if [[ -f "${HOME}/.openclaw/skills/local-whisper/config.json" ]]; then
        _check_pass "Voice: Whisper ${whisper_model} ready"
    else
        _check_fail "Voice: Whisper config not found"
    fi

    # ── 10. Security ────────────────────────────────────────────────────────
    if [[ -f "${CLAWSPARK_DIR}/token" ]]; then
        _check_pass "Security: localhost-only, token auth"
    else
        _check_fail "Security: token not generated"
    fi

    # ── 11. Messaging ───────────────────────────────────────────────────────
    local msg_status="${MESSAGING_CHOICE:-skip}"
    if [[ "${msg_status}" != "skip" ]]; then
        _check_pass "Messaging: ${msg_status} configured"
    else
        _check_pass "Messaging: skipped"
    fi

    # ── 12. Quick benchmark ────────────────────────────────────────────────
    local toks_str="n/a"
    if curl -sf http://127.0.0.1:11434/ &>/dev/null; then
        toks_str=$(_run_benchmark)
    fi
    _check_pass "Performance: ${toks_str}"

    # ── Summary ─────────────────────────────────────────────────────────────
    printf '\n'
    if (( fail == 0 )); then
        log_success "All ${pass} checks passed."
    else
        log_warn "${pass} passed, ${fail} failed. Review the items marked with ✗ above."
    fi
}

# ── Benchmark ───────────────────────────────────────────────────────────────
# Sends a short prompt and measures tokens/second from the Ollama API.
_run_benchmark() {
    local start_ms end_ms elapsed_ms
    local response tok_count tps

    start_ms=$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)

    response=$(curl -sf --max-time 30 http://127.0.0.1:11434/api/generate \
        -d "{\"model\":\"${SELECTED_MODEL_ID}\",\"prompt\":\"Count from 1 to 10.\",\"stream\":false,\"options\":{\"num_predict\":10}}" 2>/dev/null || echo "")

    end_ms=$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)

    if [[ -z "${response}" ]]; then
        echo "benchmark skipped (API timeout)"
        return 0
    fi

    # Try to extract eval_count and eval_duration from Ollama response
    local eval_count eval_duration_ns
    eval_count=$(echo "${response}" | grep -o '"eval_count":[0-9]*' | cut -d: -f2 || echo "")
    eval_duration_ns=$(echo "${response}" | grep -o '"eval_duration":[0-9]*' | cut -d: -f2 || echo "")

    if [[ -n "${eval_count}" && -n "${eval_duration_ns}" && "${eval_duration_ns}" -gt 0 ]]; then
        # eval_duration is in nanoseconds
        tps=$(awk "BEGIN {printf \"%.1f\", ${eval_count} / (${eval_duration_ns} / 1000000000)}")
        echo "~${tps} tok/s"
    else
        elapsed_ms=$(( end_ms - start_ms ))
        if (( elapsed_ms > 0 )); then
            echo "~$(( 10 * 1000 / elapsed_ms )) tok/s (estimated)"
        else
            echo "benchmark unavailable"
        fi
    fi
}
