#!/usr/bin/env bash
# lib/sandbox-commands.sh -- CLI subcommands for managing the Docker sandbox.
# Sourced by the clawspark CLI. Provides: clawspark sandbox [on|off|status|test]
set -euo pipefail

_cmd_sandbox() {
    local subcmd="${1:-status}"
    shift || true

    case "${subcmd}" in
        on)      _sandbox_on ;;
        off)     _sandbox_off ;;
        status)  _sandbox_status ;;
        test)    _sandbox_test ;;
        *)
            log_error "Unknown sandbox subcommand: ${subcmd}"
            printf '  Usage: clawspark sandbox [on|off|status|test]\n'
            exit 1
            ;;
    esac
}

# ── sandbox on ────────────────────────────────────────────────────────────────

_sandbox_on() {
    local config_file="${HOME}/.openclaw/openclaw.json"
    local sandbox_dir="${CLAWSPARK_DIR}/sandbox"

    if [[ ! -f "${config_file}" ]]; then
        log_error "Config not found at ${config_file}. Run install.sh first."
        exit 1
    fi

    # Check Docker availability
    if ! check_command docker; then
        log_error "Docker is not installed. Install Docker first to use the sandbox."
        exit 1
    fi

    if ! docker info &>/dev/null; then
        log_error "Docker daemon is not running. Start Docker first."
        exit 1
    fi

    # Build the sandbox image if it does not exist
    if ! docker image inspect clawspark-sandbox:latest &>/dev/null; then
        if [[ -f "${sandbox_dir}/Dockerfile" ]]; then
            log_info "Sandbox image not found. Building it now..."
            docker build -t clawspark-sandbox:latest "${sandbox_dir}" 2>&1 \
                | tee -a "${CLAWSPARK_LOG}"
            if ! docker image inspect clawspark-sandbox:latest &>/dev/null; then
                log_error "Image build failed. Check ${CLAWSPARK_LOG}."
                exit 1
            fi
            log_success "Sandbox image built."
        else
            log_error "Sandbox Dockerfile not found at ${sandbox_dir}/Dockerfile."
            log_error "Re-run install.sh to set up the sandbox."
            exit 1
        fi
    fi

    # Enable sandbox using the correct OpenClaw schema path: agents.defaults.sandbox
    # NOTE: Do NOT set network:"none" here -- it breaks the main agent's network access.
    # Network isolation is handled by the Docker --network=none flag in run.sh instead.
    python3 -c "
import json, sys

path = sys.argv[1]

with open(path, 'r') as f:
    cfg = json.load(f)

cfg.setdefault('agents', {}).setdefault('defaults', {})
cfg['agents']['defaults']['sandbox'] = {
    'mode': 'non-main',
    'scope': 'session',
    'docker': {
        'image': 'clawspark-sandbox:latest'
    }
}

# Clean up any invalid root-level sandbox key from previous installs
cfg.pop('sandbox', None)

with open(path, 'w') as f:
    json.dump(cfg, f, indent=2)
print('ok')
" "${config_file}" 2>> "${CLAWSPARK_LOG}" || {
        log_error "Failed to update openclaw.json."
        exit 1
    }

    # Persist sandbox state
    echo "true" > "${CLAWSPARK_DIR}/sandbox.state"

    log_success "Sandbox enabled. Sub-agent code execution runs in Docker."
    log_info "Restart to apply: clawspark restart"
}

# ── sandbox off ───────────────────────────────────────────────────────────────

_sandbox_off() {
    local config_file="${HOME}/.openclaw/openclaw.json"

    if [[ -f "${config_file}" ]]; then
        python3 -c "
import json, sys

path = sys.argv[1]

with open(path, 'r') as f:
    cfg = json.load(f)

# Remove sandbox from the correct schema path
if 'agents' in cfg and 'defaults' in cfg['agents']:
    cfg['agents']['defaults'].pop('sandbox', None)

# Also clean up any invalid root-level key
cfg.pop('sandbox', None)

with open(path, 'w') as f:
    json.dump(cfg, f, indent=2)
print('ok')
" "${config_file}" 2>> "${CLAWSPARK_LOG}" || true
    fi

    # Persist sandbox state
    echo "false" > "${CLAWSPARK_DIR}/sandbox.state"

    log_success "Sandbox disabled. Code execution will run on the host."
    log_info "Restart to apply: clawspark restart"
}

# ── sandbox status ────────────────────────────────────────────────────────────

_sandbox_status() {
    printf '\n%s%s clawspark sandbox status%s\n\n' "${BOLD}" "${BLUE}" "${RESET}"

    # Docker installed?
    if check_command docker; then
        printf '  %s✓%s Docker            installed\n' "${GREEN}" "${RESET}"
    else
        printf '  %s✗%s Docker            not installed\n' "${RED}" "${RESET}"
        printf '\n  Install Docker to enable sandbox support.\n\n'
        return
    fi

    # Docker daemon running?
    if docker info &>/dev/null; then
        printf '  %s✓%s Docker daemon     running\n' "${GREEN}" "${RESET}"
    else
        printf '  %s✗%s Docker daemon     not running\n' "${RED}" "${RESET}"
    fi

    # Sandbox image exists?
    if docker image inspect clawspark-sandbox:latest &>/dev/null; then
        local image_size
        image_size=$(docker image inspect clawspark-sandbox:latest \
            --format '{{.Size}}' 2>/dev/null || echo "0")
        # Convert bytes to MB
        local size_mb
        size_mb=$(awk "BEGIN {printf \"%.0f\", ${image_size} / 1048576}")
        printf '  %s✓%s Sandbox image     built (%s MB)\n' "${GREEN}" "${RESET}" "${size_mb}"
    else
        printf '  %s✗%s Sandbox image     not built\n' "${YELLOW}" "${RESET}"
    fi

    # Seccomp profile exists?
    local seccomp_path="${CLAWSPARK_DIR}/sandbox/seccomp-profile.json"
    if [[ -f "${seccomp_path}" ]]; then
        printf '  %s✓%s Seccomp profile   present\n' "${GREEN}" "${RESET}"
    else
        printf '  %s-%s Seccomp profile   missing\n' "${YELLOW}" "${RESET}"
    fi

    # Sandbox enabled in config?
    local config_file="${HOME}/.openclaw/openclaw.json"
    local sandbox_mode="not configured"
    if [[ -f "${config_file}" ]]; then
        sandbox_mode=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    cfg = json.load(f)
mode = cfg.get('agents', {}).get('defaults', {}).get('sandbox', {}).get('mode', 'not configured')
print(mode)
" "${config_file}" 2>/dev/null || echo "not configured")
    fi

    if [[ "${sandbox_mode}" == "not configured" ]]; then
        printf '  %s-%s Sandbox mode      %s\n' "${YELLOW}" "${RESET}" "${sandbox_mode}"
    else
        printf '  %s✓%s Sandbox mode      %s\n' "${GREEN}" "${RESET}" "${sandbox_mode}"
    fi

    # Sandbox state file
    local state="off"
    if [[ -f "${CLAWSPARK_DIR}/sandbox.state" ]]; then
        state=$(cat "${CLAWSPARK_DIR}/sandbox.state")
        [[ "${state}" == "true" ]] && state="ON" || state="off"
    fi
    printf '  %s-%s Sandbox state     %s\n' "${CYAN}" "${RESET}" "${state}"

    # Security summary
    printf '\n  %s%sSecurity constraints:%s\n' "${BOLD}" "${CYAN}" "${RESET}"
    printf '    --network=none       No network access from sandbox\n'
    printf '    --cap-drop=ALL       All Linux capabilities dropped\n'
    printf '    --read-only          Root filesystem is read-only\n'
    printf '    --pids-limit=200     Process count limited to 200\n'
    printf '    --memory=1g          Memory capped at 1 GB\n'
    printf '    --cpus=2             CPU limited to 2 cores\n'
    printf '    seccomp profile      Dangerous syscalls blocked\n'
    printf '    no-new-privileges    Privilege escalation prevented\n'

    printf '\n  Enable:  clawspark sandbox on\n'
    printf '  Disable: clawspark sandbox off\n'
    printf '  Test:    clawspark sandbox test\n\n'
}

# ── sandbox test ──────────────────────────────────────────────────────────────

_sandbox_test() {
    printf '\n%s%s clawspark sandbox test%s\n\n' "${BOLD}" "${BLUE}" "${RESET}"

    # Preflight checks
    if ! check_command docker; then
        log_error "Docker is not installed."
        exit 1
    fi

    if ! docker info &>/dev/null; then
        log_error "Docker daemon is not running."
        exit 1
    fi

    if ! docker image inspect clawspark-sandbox:latest &>/dev/null; then
        log_error "Sandbox image not found. Run: clawspark sandbox on"
        exit 1
    fi

    local sandbox_dir="${CLAWSPARK_DIR}/sandbox"
    local seccomp_path="${sandbox_dir}/seccomp-profile.json"
    local seccomp_opt=""
    if [[ -f "${seccomp_path}" ]]; then
        seccomp_opt="--security-opt=seccomp=${seccomp_path}"
    fi

    local passed=0
    local failed=0

    # Test 1: Basic Python execution
    printf '  %s[1/5]%s Python execution ... ' "${CYAN}" "${RESET}"
    local result
    result=$(docker run --rm \
        --read-only \
        --tmpfs /tmp:size=100m \
        --tmpfs /sandbox/work:size=500m \
        --network=none \
        --cap-drop=ALL \
        --security-opt=no-new-privileges \
        ${seccomp_opt} \
        --memory=1g \
        --cpus=2 \
        --pids-limit=200 \
        clawspark-sandbox:latest \
        python3 -c "print('sandbox_ok')" 2>&1 || echo "FAIL")

    if [[ "${result}" == *"sandbox_ok"* ]]; then
        printf '%sPASS%s\n' "${GREEN}" "${RESET}"
        passed=$(( passed + 1 ))
    else
        printf '%sFAIL%s\n' "${RED}" "${RESET}"
        failed=$(( failed + 1 ))
    fi

    # Test 2: Network isolation (should fail to reach the internet)
    printf '  %s[2/5]%s Network isolation ... ' "${CYAN}" "${RESET}"
    result=$(docker run --rm \
        --read-only \
        --tmpfs /tmp:size=100m \
        --network=none \
        --cap-drop=ALL \
        --security-opt=no-new-privileges \
        ${seccomp_opt} \
        --memory=1g \
        --cpus=2 \
        --pids-limit=200 \
        clawspark-sandbox:latest \
        python3 -c "
import urllib.request, sys
try:
    urllib.request.urlopen('http://1.1.1.1', timeout=3)
    print('NETWORK_OPEN')
except Exception:
    print('NETWORK_BLOCKED')
" 2>&1 || echo "NETWORK_BLOCKED")

    if [[ "${result}" == *"NETWORK_BLOCKED"* ]]; then
        printf '%sPASS%s (no outbound access)\n' "${GREEN}" "${RESET}"
        passed=$(( passed + 1 ))
    else
        printf '%sFAIL%s (network was reachable)\n' "${RED}" "${RESET}"
        failed=$(( failed + 1 ))
    fi

    # Test 3: Read-only filesystem
    printf '  %s[3/5]%s Read-only rootfs ... ' "${CYAN}" "${RESET}"
    result=$(docker run --rm \
        --read-only \
        --tmpfs /tmp:size=100m \
        --tmpfs /sandbox/work:size=500m \
        --network=none \
        --cap-drop=ALL \
        --security-opt=no-new-privileges \
        ${seccomp_opt} \
        --memory=1g \
        --cpus=2 \
        --pids-limit=200 \
        clawspark-sandbox:latest \
        python3 -c "
import os, sys
try:
    with open('/etc/test_write', 'w') as f:
        f.write('test')
    print('WRITABLE')
except (OSError, PermissionError):
    print('READONLY')
" 2>&1 || echo "READONLY")

    if [[ "${result}" == *"READONLY"* ]]; then
        printf '%sPASS%s (writes blocked)\n' "${GREEN}" "${RESET}"
        passed=$(( passed + 1 ))
    else
        printf '%sFAIL%s (rootfs was writable)\n' "${RED}" "${RESET}"
        failed=$(( failed + 1 ))
    fi

    # Test 4: tmpfs is writable (sandbox work area should work)
    printf '  %s[4/5]%s Tmpfs work area ... ' "${CYAN}" "${RESET}"
    result=$(docker run --rm \
        --read-only \
        --tmpfs /tmp:size=100m \
        --tmpfs /sandbox/work:size=500m \
        --network=none \
        --cap-drop=ALL \
        --security-opt=no-new-privileges \
        ${seccomp_opt} \
        --memory=1g \
        --cpus=2 \
        --pids-limit=200 \
        clawspark-sandbox:latest \
        python3 -c "
with open('/sandbox/work/test.txt', 'w') as f:
    f.write('hello')
with open('/sandbox/work/test.txt', 'r') as f:
    data = f.read()
print('TMPFS_OK' if data == 'hello' else 'TMPFS_FAIL')
" 2>&1 || echo "TMPFS_FAIL")

    if [[ "${result}" == *"TMPFS_OK"* ]]; then
        printf '%sPASS%s (work area writable)\n' "${GREEN}" "${RESET}"
        passed=$(( passed + 1 ))
    else
        printf '%sFAIL%s (work area not writable)\n' "${RED}" "${RESET}"
        failed=$(( failed + 1 ))
    fi

    # Test 5: Non-root user
    printf '  %s[5/5]%s Non-root user ... ' "${CYAN}" "${RESET}"
    result=$(docker run --rm \
        --read-only \
        --tmpfs /tmp:size=100m \
        --tmpfs /sandbox/work:size=500m \
        --network=none \
        --cap-drop=ALL \
        --security-opt=no-new-privileges \
        ${seccomp_opt} \
        --memory=1g \
        --cpus=2 \
        --pids-limit=200 \
        clawspark-sandbox:latest \
        python3 -c "
import os
uid = os.getuid()
print('NONROOT' if uid != 0 else 'ROOT')
" 2>&1 || echo "ROOT")

    if [[ "${result}" == *"NONROOT"* ]]; then
        printf '%sPASS%s (running as non-root)\n' "${GREEN}" "${RESET}"
        passed=$(( passed + 1 ))
    else
        printf '%sFAIL%s (running as root)\n' "${RED}" "${RESET}"
        failed=$(( failed + 1 ))
    fi

    # Summary
    printf '\n'
    if (( failed == 0 )); then
        print_box \
            "${GREEN}${BOLD}All ${passed} tests passed${RESET}" \
            "" \
            "The sandbox is working correctly." \
            "Agent-generated code will execute in a hardened container."
    else
        print_box \
            "${RED}${BOLD}${failed} of $(( passed + failed )) tests failed${RESET}" \
            "" \
            "Some sandbox security checks did not pass." \
            "Review Docker configuration and try again."
    fi
    printf '\n'

    # Return non-zero if any test failed
    (( failed > 0 )) && return 1 || return 0
}
