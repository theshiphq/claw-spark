#!/usr/bin/env bash
set -euo pipefail

diagnose_system() {
    log_info "Running full system diagnostic..."
    hr

    local pass=0
    local fail=0
    local warn=0
    local report_lines=()

    _check_pass() {
        printf '  %s✓%s %s\n' "${GREEN}" "${RESET}" "$1"
        pass=$(( pass + 1 ))
        report_lines+=("PASS: $1")
    }
    _check_fail() {
        printf '  %s✗%s %s\n' "${RED}" "${RESET}" "$1"
        fail=$(( fail + 1 ))
        report_lines+=("FAIL: $1")
    }
    _check_warn() {
        printf '  %s!%s %s\n' "${YELLOW}" "${RESET}" "$1"
        warn=$(( warn + 1 ))
        report_lines+=("WARN: $1")
    }
    _section() {
        printf '\n  %s%s── %s ──%s\n\n' "${BOLD}" "${CYAN}" "$1" "${RESET}"
        report_lines+=("" "=== $1 ===")
    }

    printf '\n'

    _DIAG_OS=$(uname -s 2>/dev/null || echo "unknown")

    _diagnose_system_requirements
    _diagnose_gpu_hardware
    _diagnose_ollama
    _diagnose_openclaw
    _diagnose_skills
    _diagnose_network
    _diagnose_security
    _diagnose_logs

    printf '\n'
    hr

    if (( fail == 0 && warn == 0 )); then
        log_success "All ${pass} checks passed. System is healthy."
    elif (( fail == 0 )); then
        log_success "${pass} passed, ${warn} warning(s). System is functional."
    else
        log_warn "${pass} passed, ${warn} warning(s), ${fail} failed. Review items marked with ✗ above."
    fi

    _write_report
}

_diagnose_system_requirements() {
    _section "System Requirements"

    local kernel_ver
    kernel_ver=$(uname -r 2>/dev/null || echo "unknown")
    case "${_DIAG_OS}" in
        Linux)  _check_pass "OS: Linux (${kernel_ver})" ;;
        Darwin) _check_pass "OS: macOS (${kernel_ver})" ;;
        *)      _check_warn "OS: ${_DIAG_OS} (${kernel_ver}) — untested platform" ;;
    esac

    local bash_ver="${BASH_VERSION:-unknown}"
    local bash_major="${bash_ver%%.*}"
    if [[ "${bash_major}" =~ ^[0-9]+$ ]] && (( bash_major >= 3 )); then
        local bash_minor="${bash_ver#*.}"
        bash_minor="${bash_minor%%.*}"
        if (( bash_major > 3 )) || (( bash_minor >= 2 )); then
            _check_pass "Bash: ${bash_ver} (>= 3.2)"
        else
            _check_fail "Bash: ${bash_ver} (needs >= 3.2)"
        fi
    else
        _check_fail "Bash: ${bash_ver} (needs >= 3.2)"
    fi

    if check_command node; then
        local node_ver
        node_ver=$(node --version 2>/dev/null || echo "v0")
        local node_major="${node_ver#v}"
        node_major="${node_major%%.*}"
        if [[ "${node_major}" =~ ^[0-9]+$ ]] && (( node_major >= 22 )); then
            _check_pass "Node.js: ${node_ver} (>= 22)"
        else
            _check_fail "Node.js: ${node_ver} (needs >= 22)"
        fi
    else
        _check_fail "Node.js: not installed"
    fi

    if check_command npm; then
        local npm_ver
        npm_ver=$(npm --version 2>/dev/null || echo "unknown")
        _check_pass "npm: ${npm_ver}"
    else
        _check_fail "npm: not installed"
    fi

    if check_command python3; then
        local py_ver
        py_ver=$(python3 --version 2>/dev/null | awk '{print $2}' || echo "unknown")
        _check_pass "Python3: ${py_ver}"
    else
        _check_warn "Python3: not installed (optional but recommended)"
    fi

    if check_command curl; then
        _check_pass "curl: available"
    else
        _check_fail "curl: not installed"
    fi

    local free_gb=0
    if check_command df; then
        local free_kb
        free_kb=$(df -k "${HOME}" 2>/dev/null | awk 'NR==2{print $4}' || echo 0)
        if [[ "${free_kb}" =~ ^[0-9]+$ ]]; then
            free_gb=$(( free_kb / 1024 / 1024 ))
        fi
    fi
    if (( free_gb >= 20 )); then
        _check_pass "Disk space: ${free_gb}GB free"
    elif (( free_gb > 0 )); then
        _check_warn "Disk space: ${free_gb}GB free (< 20GB recommended)"
    else
        _check_warn "Disk space: unable to determine"
    fi

    local total_mem_mb=0 avail_mem_mb=0
    if [[ -f /proc/meminfo ]]; then
        local total_kb avail_kb
        total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
        avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
        total_mem_mb=$(( total_kb / 1024 ))
        avail_mem_mb=$(( avail_kb / 1024 ))
    elif check_command sysctl; then
        local mem_bytes
        mem_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        total_mem_mb=$(( mem_bytes / 1024 / 1024 ))
        if check_command vm_stat; then
            local vm_output page_size free_pages
            vm_output=$(vm_stat 2>/dev/null || echo "")
            page_size=$(echo "${vm_output}" | awk '/page size/ {print $8}' || echo 4096)
            page_size="${page_size:-4096}"
            free_pages=$(echo "${vm_output}" | awk '/Pages free:/ {gsub(/\./,"",$3); print $3}' || echo 0)
            avail_mem_mb=$(( free_pages * page_size / 1024 / 1024 ))
        fi
    fi
    local total_gb=$(( total_mem_mb / 1024 ))
    local avail_gb=$(( avail_mem_mb / 1024 ))
    if (( total_mem_mb > 0 )); then
        _check_pass "Memory: ${avail_gb}GB available / ${total_gb}GB total"
    else
        _check_warn "Memory: unable to determine"
    fi
}

_diagnose_gpu_hardware() {
    _section "GPU & Hardware"

    if check_command nvidia-smi; then
        local gpu_name gpu_vram driver_ver cuda_ver
        gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits 2>/dev/null | head -n1 | xargs || echo "unknown")
        gpu_vram=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 | xargs || echo "0")
        driver_ver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>/dev/null | head -n1 | xargs || echo "unknown")
        cuda_ver=$(nvidia-smi 2>/dev/null | sed -n 's/.*CUDA Version: \([0-9.]*\).*/\1/p' | head -n1)
        cuda_ver="${cuda_ver:-unknown}"

        _check_pass "GPU: ${gpu_name}"
        if [[ "${gpu_vram}" =~ ^[0-9]+$ ]] && (( gpu_vram > 0 )); then
            local vram_gb=$(( gpu_vram / 1024 ))
            _check_pass "VRAM: ${vram_gb}GB (${gpu_vram}MB)"
        else
            _check_warn "VRAM: unable to determine (unified memory?)"
        fi
        _check_pass "Driver: ${driver_ver}, CUDA: ${cuda_ver}"
    elif [[ "${_DIAG_OS}" == "Darwin" ]]; then
        if check_command system_profiler; then
            local gpu_info
            gpu_info=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Chipset Model|VRAM|Metal" || echo "")
            if [[ -n "${gpu_info}" ]]; then
                local chip
                chip=$(echo "${gpu_info}" | grep "Chipset Model" | head -n1 | sed 's/.*: //' | xargs || echo "unknown")
                _check_pass "GPU: ${chip} (macOS)"
            else
                _check_warn "GPU: unable to query system_profiler"
            fi
        else
            _check_warn "GPU: system_profiler not available"
        fi
    else
        _check_warn "GPU: no NVIDIA GPU detected (nvidia-smi not found)"
    fi
}

_diagnose_ollama() {
    _section "Ollama Health"

    if check_command ollama; then
        local ollama_ver
        ollama_ver=$(ollama --version 2>/dev/null | awk '{print $NF}' || echo "unknown")
        _check_pass "Ollama binary: ${ollama_ver}"
    else
        _check_fail "Ollama binary: not installed"
        return 0
    fi

    if curl -sf --max-time 5 http://127.0.0.1:11434/ &>/dev/null; then
        _check_pass "Ollama API: responding at 127.0.0.1:11434"
    else
        _check_fail "Ollama API: not responding at 127.0.0.1:11434"
        return 0
    fi

    local models_output first_model=""
    models_output=$(ollama list 2>/dev/null || echo "")
    if [[ -n "${models_output}" ]]; then
        local model_count
        model_count=$(echo "${models_output}" | tail -n +2 | grep -c '.' || echo 0)
        _check_pass "Ollama models: ${model_count} loaded"
        if (( model_count > 0 )); then
            first_model=$(echo "${models_output}" | awk 'NR==2{print $1}')
            echo "${models_output}" | tail -n +2 | while IFS= read -r line; do
                local name size
                name=$(echo "${line}" | awk '{print $1}')
                size=$(echo "${line}" | awk '{print $3, $4}')
                printf '      %s%s%s  %s\n' "${CYAN}" "${name}" "${RESET}" "${size}"
            done
        fi
    else
        _check_warn "Ollama models: unable to list"
    fi

    if [[ -z "${first_model}" ]]; then
        _check_warn "Inference test: no models available"
        return 0
    fi

    printf '    %sRunning inference test...%s ' "${BLUE}" "${RESET}"
    local start_s end_s elapsed_ms
    start_s=$(date +%s 2>/dev/null || echo 0)

    local safe_model
    safe_model=$(printf '%s' "${first_model}" | sed 's/\\/\\\\/g; s/"/\\"/g')

    local test_response
    test_response=$(curl -sf --max-time 30 http://127.0.0.1:11434/api/generate \
        -d "{\"model\":\"${safe_model}\",\"prompt\":\"Say hi\",\"stream\":false,\"options\":{\"num_predict\":5}}" 2>/dev/null || echo "")

    end_s=$(date +%s 2>/dev/null || echo 0)

    if [[ -n "${test_response}" ]]; then
        elapsed_ms=$(( (end_s - start_s) * 1000 ))
        printf '%s✓%s ~%sms\n' "${GREEN}" "${RESET}" "${elapsed_ms}"
        _check_pass "Inference test: ~${elapsed_ms}ms response time"
    else
        printf '%s✗%s\n' "${RED}" "${RESET}"
        _check_warn "Inference test: timed out or no models available"
    fi

    local ollama_dir=""
    if [[ -d "${HOME}/.ollama/models" ]]; then
        ollama_dir="${HOME}/.ollama/models"
    elif [[ -d "/usr/share/ollama/.ollama/models" ]]; then
        ollama_dir="/usr/share/ollama/.ollama/models"
    fi
    if [[ -n "${ollama_dir}" ]]; then
        local ollama_size
        ollama_size=$(du -sh "${ollama_dir}" 2>/dev/null | awk '{print $1}' || echo "unknown")
        _check_pass "Ollama storage: ${ollama_size} (${ollama_dir})"
    else
        _check_warn "Ollama storage: directory not found"
    fi
}

_diagnose_openclaw() {
    _section "OpenClaw Health"

    if check_command openclaw; then
        local oc_ver
        oc_ver=$(openclaw --version 2>/dev/null || echo "unknown")
        _check_pass "OpenClaw binary: ${oc_ver}"
    else
        _check_fail "OpenClaw binary: not installed"
        return 0
    fi

    local config_file="${HOME}/.openclaw/openclaw.json"
    if [[ -f "${config_file}" ]]; then
        if python3 -c "import json, sys; json.load(open(sys.argv[1]))" "${config_file}" 2>/dev/null; then
            _check_pass "Config: ${config_file} (valid JSON)"
        else
            _check_fail "Config: ${config_file} (invalid JSON)"
        fi
    else
        _check_fail "Config: ${config_file} not found"
    fi

    local gw_running=false
    if systemctl is-active --quiet clawspark-gateway.service 2>/dev/null; then
        _check_pass "Gateway process: running (systemd)"
        gw_running=true
    elif [[ -f "${CLAWSPARK_DIR}/gateway.pid" ]]; then
        local gw_pid
        gw_pid=$(cat "${CLAWSPARK_DIR}/gateway.pid" 2>/dev/null || echo "")
        if [[ -n "${gw_pid}" ]] && kill -0 "${gw_pid}" 2>/dev/null; then
            _check_pass "Gateway process: running (PID ${gw_pid})"
            gw_running=true
        else
            _check_fail "Gateway process: not running (stale PID file)"
        fi
    else
        _check_fail "Gateway process: not running"
    fi

    if systemctl is-active --quiet clawspark-nodehost.service 2>/dev/null; then
        _check_pass "Node host process: running (systemd)"
    elif [[ -f "${CLAWSPARK_DIR}/node.pid" ]]; then
        local node_pid
        node_pid=$(cat "${CLAWSPARK_DIR}/node.pid" 2>/dev/null || echo "")
        if [[ -n "${node_pid}" ]] && kill -0 "${node_pid}" 2>/dev/null; then
            _check_pass "Node host process: running (PID ${node_pid})"
        else
            _check_fail "Node host process: not running (stale PID file)"
        fi
    else
        _check_fail "Node host process: not running"
    fi

    if [[ -f "${config_file}" ]] && check_command python3; then
        local restrictions
        restrictions=$(python3 -c "
import json, sys
c = json.load(open(sys.argv[1]))
fs_only = c.get('tools',{}).get('fs',{}).get('workspaceOnly', False)
deny_cmds = c.get('gateway',{}).get('nodes',{}).get('denyCommands', [])
print('ws=' + str(fs_only) + ' deny=' + str(len(deny_cmds)))
" "${config_file}" 2>/dev/null || echo "")

        if [[ "${restrictions}" == *"ws=True"* ]]; then
            _check_pass "Tool restriction: workspaceOnly enabled"
        else
            _check_warn "Tool restriction: workspaceOnly not set"
        fi

        if [[ "${restrictions}" =~ deny=([0-9]+) ]]; then
            local deny_count="${BASH_REMATCH[1]}"
            if (( deny_count > 0 )); then
                _check_pass "Tool restriction: ${deny_count} denied command patterns"
            else
                _check_warn "Tool restriction: no denyCommands configured"
            fi
        fi
    fi

    local openclaw_dir="${HOME}/.openclaw"
    if [[ -f "${openclaw_dir}/SOUL.md" ]]; then
        _check_pass "SOUL.md: present"
    else
        _check_warn "SOUL.md: not found in ${openclaw_dir}"
    fi

    if [[ -f "${openclaw_dir}/TOOLS.md" ]]; then
        _check_pass "TOOLS.md: present"
    else
        _check_warn "TOOLS.md: not found in ${openclaw_dir}"
    fi
}

_diagnose_skills() {
    _section "Skills Health"

    local skills_dir="${HOME}/.openclaw/skills"
    local skill_count=0

    if [[ -d "${skills_dir}" ]]; then
        skill_count=$(find "${skills_dir}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
        _check_pass "Installed skills: ${skill_count} (${skills_dir})"

        local missing=0
        if [[ -f "${CLAWSPARK_DIR}/skills.yaml" ]]; then
            local slug
            while IFS= read -r slug; do
                [[ -z "${slug}" ]] && continue
                if [[ ! -d "${skills_dir}/${slug}" ]]; then
                    _check_warn "Skill directory missing: ${slug}"
                    missing=$(( missing + 1 ))
                fi
            done < <(_parse_enabled_skills "${CLAWSPARK_DIR}/skills.yaml")
            if (( missing == 0 && skill_count > 0 )); then
                _check_pass "All configured skills have directories"
            fi
        fi
    else
        _check_warn "Skills directory not found: ${skills_dir}"
    fi

    local suspicious=0
    if [[ -d "${skills_dir}" ]]; then
        local skill_dir
        for skill_dir in "${skills_dir}"/*/; do
            [[ ! -d "${skill_dir}" ]] && continue
            local skill_name
            skill_name=$(basename "${skill_dir}")

            if grep -rqlE '(curl|wget|nc|ncat)\s+[^|]*\.(onion|i2p|bit)' "${skill_dir}" 2>/dev/null; then
                _check_fail "Suspicious skill '${skill_name}': darknet URL pattern"
                suspicious=$(( suspicious + 1 ))
            fi
            if grep -rqlE 'eval\s*\(\s*(atob|Buffer\.from)' "${skill_dir}" 2>/dev/null; then
                _check_fail "Suspicious skill '${skill_name}': obfuscated eval pattern"
                suspicious=$(( suspicious + 1 ))
            fi
            if grep -rqlE '(exfiltrate|steal|keylog|reverse.shell)' "${skill_dir}" 2>/dev/null; then
                _check_fail "Suspicious skill '${skill_name}': malicious keyword detected"
                suspicious=$(( suspicious + 1 ))
            fi
        done
        if (( suspicious == 0 && skill_count > 0 )); then
            _check_pass "Skill audit: no suspicious patterns found"
        fi
    fi
}

_diagnose_network() {
    _section "Network & Ports"

    _check_port() {
        local port="$1"
        local label="$2"
        if check_command lsof; then
            local proc
            proc=$(lsof -i :"${port}" -sTCP:LISTEN -t 2>/dev/null | head -n1 || echo "")
            if [[ -n "${proc}" ]]; then
                local pname
                pname=$(ps -p "${proc}" -o comm= 2>/dev/null || echo "unknown")
                _check_pass "Port ${port} (${label}): in use by ${pname} (PID ${proc})"
            else
                _check_warn "Port ${port} (${label}): not in use"
            fi
        elif check_command ss; then
            if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
                _check_pass "Port ${port} (${label}): in use"
            else
                _check_warn "Port ${port} (${label}): not in use"
            fi
        elif check_command netstat; then
            if netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
                _check_pass "Port ${port} (${label}): in use"
            else
                _check_warn "Port ${port} (${label}): not in use"
            fi
        else
            _check_warn "Port ${port} (${label}): unable to check (no lsof/ss/netstat)"
        fi
    }

    _check_port 11434 "Ollama"
    _check_port 18789 "OpenClaw node"
    _check_port 8900  "ClawMetry"

    if check_command curl; then
        if curl -sf --max-time 5 https://registry.npmjs.org/ &>/dev/null; then
            _check_pass "Internet: reachable (npmjs.org)"
        elif curl -sf --max-time 5 https://github.com &>/dev/null; then
            _check_pass "Internet: reachable (github.com)"
        else
            _check_warn "Internet: unreachable (air-gapped or offline)"
        fi
    else
        _check_warn "Internet: cannot check (curl not available)"
    fi

    if [[ -f "${CLAWSPARK_DIR}/airgap.state" ]]; then
        local airgap_state
        airgap_state=$(cat "${CLAWSPARK_DIR}/airgap.state" 2>/dev/null || echo "unknown")
        if [[ "${airgap_state}" == "true" ]]; then
            _check_pass "Air-gap: enabled"
        else
            _check_pass "Air-gap: disabled"
        fi
    else
        _check_pass "Air-gap: not configured"
    fi
}

_diagnose_security() {
    _section "Security"

    local token_file="${CLAWSPARK_DIR}/token"
    if [[ -f "${token_file}" ]]; then
        local perms
        perms=$(stat -f '%Lp' "${token_file}" 2>/dev/null || stat -c '%a' "${token_file}" 2>/dev/null || echo "unknown")
        if [[ "${perms}" == "600" ]]; then
            _check_pass "Token file: exists, permissions ${perms}"
        else
            _check_warn "Token file: exists, permissions ${perms} (should be 600)"
        fi
    else
        _check_fail "Token file: not found at ${token_file}"
    fi

    local bind_value=""
    if check_command systemctl && systemctl cat clawspark-gateway.service &>/dev/null; then
        bind_value=$(systemctl show -p ExecStart clawspark-gateway.service 2>/dev/null \
            | grep -oE '\-\-bind[= ]*(loopback|[^ ]*)' | head -1 || echo "")
    fi
    if [[ -z "${bind_value}" ]] && [[ -f "${CLAWSPARK_DIR}/gateway.pid" ]]; then
        local gw_pid
        gw_pid=$(cat "${CLAWSPARK_DIR}/gateway.pid" 2>/dev/null || echo "")
        if [[ -n "${gw_pid}" ]] && [[ -d "/proc/${gw_pid}" ]]; then
            bind_value=$(tr '\0' ' ' < "/proc/${gw_pid}/cmdline" 2>/dev/null \
                | grep -oE '\-\-bind[= ]*(loopback|[^ ]*)' | head -1 || echo "")
        elif [[ -n "${gw_pid}" ]]; then
            bind_value=$(ps -p "${gw_pid}" -o args= 2>/dev/null \
                | grep -oE '\-\-bind[= ]*(loopback|[^ ]*)' | head -1 || echo "")
        fi
    fi
    if [[ "${bind_value}" == *"loopback"* ]]; then
        _check_pass "Gateway binding: localhost only (--bind loopback)"
    elif [[ -n "${bind_value}" ]]; then
        _check_warn "Gateway binding: ${bind_value} (expected --bind loopback)"
    else
        _check_warn "Gateway binding: unable to determine (process not running or no --bind flag)"
    fi

    if check_command ufw; then
        local ufw_status
        ufw_status=$(sudo -n ufw status 2>/dev/null | head -n1 || echo "")
        if [[ "${ufw_status}" == *"active"* ]]; then
            _check_pass "UFW firewall: active"
        elif [[ "${ufw_status}" == *"inactive"* ]]; then
            _check_warn "UFW firewall: inactive"
        else
            _check_warn "UFW firewall: unable to determine status"
        fi
    else
        _check_warn "UFW firewall: not installed"
    fi

    if [[ -f "${CLAWSPARK_DIR}/sandbox.state" ]]; then
        local sandbox_state
        sandbox_state=$(cat "${CLAWSPARK_DIR}/sandbox.state" 2>/dev/null || echo "unknown")
        if [[ "${sandbox_state}" == "true" ]]; then
            _check_pass "Sandbox: enabled"
        else
            _check_pass "Sandbox: disabled (enable with 'clawspark sandbox on')"
        fi
    else
        _check_warn "Sandbox: not configured"
    fi
}

_diagnose_logs() {
    _section "Logs Analysis"

    _check_log_errors() {
        local logfile="$1" label="$2"
        if [[ -f "${logfile}" ]]; then
            local errors
            errors=$(grep -i 'error' "${logfile}" 2>/dev/null | tail -n 5 || echo "")
            if [[ -n "${errors}" ]]; then
                _check_warn "${label}: recent errors found"
                printf '      %s--- Last 5 errors ---%s\n' "${YELLOW}" "${RESET}"
                echo "${errors}" | while IFS= read -r eline; do
                    printf '      %s\n' "${eline}"
                done
            else
                _check_pass "${label}: no errors"
            fi
        else
            _check_warn "${label}: file not found"
        fi
    }

    _check_log_errors "${CLAWSPARK_DIR}/gateway.log" "gateway.log"
    _check_log_errors "${CLAWSPARK_DIR}/install.log" "install.log"

    local oom_found=false port_found=false model_found=false
    local logfile
    for logfile in "${CLAWSPARK_DIR}/gateway.log" "${CLAWSPARK_DIR}/install.log"; do
        [[ ! -f "${logfile}" ]] && continue
        if grep -qiE '(out of memory|oom|killed process|cannot allocate|address already in use|port.*in use|EADDRINUSE|model.*not found|pull.*failed|no such model)' "${logfile}" 2>/dev/null; then
            grep -qiE '(out of memory|oom|killed process|cannot allocate)' "${logfile}" 2>/dev/null && oom_found=true
            grep -qiE '(address already in use|port.*in use|EADDRINUSE)' "${logfile}" 2>/dev/null && port_found=true
            grep -qiE '(model.*not found|pull.*failed|no such model)' "${logfile}" 2>/dev/null && model_found=true
        fi
    done

    if ${oom_found}; then
        _check_fail "Log pattern: OOM (out of memory) errors detected"
    fi
    if ${port_found}; then
        _check_warn "Log pattern: port-in-use errors detected"
    fi
    if ${model_found}; then
        _check_warn "Log pattern: model-not-found errors detected"
    fi
    if ! ${oom_found} && ! ${port_found} && ! ${model_found}; then
        _check_pass "Log patterns: no common error patterns detected"
    fi
}

_write_report() {
    mkdir -p "${CLAWSPARK_DIR}"

    local report_file="${CLAWSPARK_DIR}/diagnose-report.txt"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    {
        echo "ClawSpark Diagnostic Report"
        echo "Generated: ${timestamp}"
        echo "OS: $(uname -s 2>/dev/null || echo 'unknown') $(uname -r 2>/dev/null || echo '')"
        echo "Bash: ${BASH_VERSION:-unknown}"
        echo "========================================="
        for line in "${report_lines[@]}"; do
            echo "${line}"
        done
        echo ""
        echo "========================================="
        echo "Pass: ${pass}  Warn: ${warn}  Fail: ${fail}"
    } > "${report_file}"

    printf '\n'
    log_success "Debug report saved to: ${report_file}"
    log_info "Share this file when reporting issues."
}
