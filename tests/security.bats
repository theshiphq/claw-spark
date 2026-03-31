#!/usr/bin/env bats
# security.bats -- Tests for security functions (sources real lib/secure.sh).

load test_helper

setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export CLAWSPARK_DIR="${TEST_TEMP_DIR}/.clawspark"
    export CLAWSPARK_LOG="${CLAWSPARK_DIR}/install.log"
    export CLAWSPARK_DEFAULTS="true"
    export HOME="${TEST_TEMP_DIR}"

    mkdir -p "${CLAWSPARK_DIR}/lib"
    mkdir -p "${HOME}/.openclaw"

    if [[ ! -f "${PROJECT_ROOT}/lib/common.sh" ]]; then
        echo "ERROR: lib/common.sh not found at ${PROJECT_ROOT}" >&2
        return 1
    fi
    cp "${PROJECT_ROOT}/lib/common.sh" "${CLAWSPARK_DIR}/lib/common.sh"
    cp "${PROJECT_ROOT}/lib/secure.sh" "${CLAWSPARK_DIR}/lib/secure.sh"

    source "${CLAWSPARK_DIR}/lib/common.sh"
    source "${CLAWSPARK_DIR}/lib/secure.sh"

    echo '{}' > "${HOME}/.openclaw/openclaw.json"
}

# ── Token generation via secure_setup ────────────────────────────────────────

@test "secure_setup creates a token file" {
    secure_setup 2>/dev/null
    [ -f "${CLAWSPARK_DIR}/token" ]
}

@test "secure_setup generates a 64 hex char token" {
    secure_setup 2>/dev/null
    local content
    content=$(cat "${CLAWSPARK_DIR}/token" | tr -d '\n')
    [[ "$content" =~ ^[0-9a-f]{64}$ ]]
}

@test "token file permissions are 600" {
    secure_setup 2>/dev/null
    local perms
    perms=$(_get_permissions "${CLAWSPARK_DIR}/token")
    [ "$perms" = "600" ]
}

@test "token file is not world-readable" {
    secure_setup 2>/dev/null
    local perms
    perms=$(_get_permissions "${CLAWSPARK_DIR}/token")
    [[ "${perms: -1}" == "0" ]]
}

@test "secure_setup does not overwrite existing token" {
    echo "original-token-value" > "${CLAWSPARK_DIR}/token"
    secure_setup 2>/dev/null
    run cat "${CLAWSPARK_DIR}/token"
    [[ "$output" == "original-token-value" ]]
}

# ── CLAWSPARK_DIR permissions via secure_setup ────────────────────────────────

@test "secure_setup restricts CLAWSPARK_DIR to 700" {
    secure_setup 2>/dev/null
    local perms
    perms=$(_get_permissions "${CLAWSPARK_DIR}")
    [ "$perms" = "700" ]
}

# ── Tool hardening via _harden_tool_access ────────────────────────────────────

@test "_harden_tool_access applies deny commands" {
    _harden_tool_access 2>/dev/null
    local config_file="${HOME}/.openclaw/openclaw.json"
    run python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    cfg = json.load(f)
deny = cfg['gateway']['nodes']['denyCommands']
assert 'rm -rf /' in deny
assert 'passwd' in deny
assert 'cat /etc/shadow' in deny
print('ok')
" "${config_file}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "_harden_tool_access blocks package installation" {
    _harden_tool_access 2>/dev/null
    local config_file="${HOME}/.openclaw/openclaw.json"
    run python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    cfg = json.load(f)
deny = cfg['gateway']['nodes']['denyCommands']
assert 'apt install' in deny
assert 'pip install' in deny
assert 'npm install -g' in deny
print('ok')
" "${config_file}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

@test "_harden_tool_access sets workspaceOnly" {
    _harden_tool_access 2>/dev/null
    local config_file="${HOME}/.openclaw/openclaw.json"
    run python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    cfg = json.load(f)
assert cfg['tools']['fs']['workspaceOnly'] is True
print('ok')
" "${config_file}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok"* ]]
}

# ── Air-gap state ─────────────────────────────────────────────────────────────

@test "airgap state file can be created" {
    echo "true" > "${CLAWSPARK_DIR}/airgap.state"
    [ -f "${CLAWSPARK_DIR}/airgap.state" ]
    run cat "${CLAWSPARK_DIR}/airgap.state"
    [ "$output" = "true" ]
}

@test "airgap state toggles to false" {
    echo "true" > "${CLAWSPARK_DIR}/airgap.state"
    echo "false" > "${CLAWSPARK_DIR}/airgap.state"
    run cat "${CLAWSPARK_DIR}/airgap.state"
    [ "$output" = "false" ]
}
