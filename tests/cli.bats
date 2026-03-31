#!/usr/bin/env bats
# cli.bats -- Tests for CLI command routing and top-level behavior.

load test_helper

CLAWSPARK_BIN="${PROJECT_ROOT}/clawspark"

# ── Version ───────────────────────────────────────────────────────────────────

@test "--version outputs version string" {
    run bash -c "export HOME='${TEST_TEMP_DIR}'; export CLAWSPARK_DIR='${CLAWSPARK_DIR}'; bash '${CLAWSPARK_BIN}' --version"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^clawspark\ v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "-v outputs version string" {
    run bash -c "export HOME='${TEST_TEMP_DIR}'; export CLAWSPARK_DIR='${CLAWSPARK_DIR}'; bash '${CLAWSPARK_BIN}' -v"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^clawspark\ v ]]
}

@test "version command outputs version string" {
    run bash -c "export HOME='${TEST_TEMP_DIR}'; export CLAWSPARK_DIR='${CLAWSPARK_DIR}'; bash '${CLAWSPARK_BIN}' version"
    [ "$status" -eq 0 ]
    [[ "$output" == *"clawspark v"* ]]
}

# ── Help ──────────────────────────────────────────────────────────────────────

@test "--help outputs usage information" {
    run bash -c "export HOME='${TEST_TEMP_DIR}'; export CLAWSPARK_DIR='${CLAWSPARK_DIR}'; bash '${CLAWSPARK_BIN}' --help"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Commands:"* ]]
}

@test "help command outputs usage information" {
    run bash -c "export HOME='${TEST_TEMP_DIR}'; export CLAWSPARK_DIR='${CLAWSPARK_DIR}'; bash '${CLAWSPARK_BIN}' help"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "-h outputs usage information" {
    run bash -c "export HOME='${TEST_TEMP_DIR}'; export CLAWSPARK_DIR='${CLAWSPARK_DIR}'; bash '${CLAWSPARK_BIN}' -h"
    [ "$status" -eq 0 ]
    [[ "$output" == *"clawspark"* ]]
}

@test "no arguments shows help" {
    run bash -c "export HOME='${TEST_TEMP_DIR}'; export CLAWSPARK_DIR='${CLAWSPARK_DIR}'; bash '${CLAWSPARK_BIN}'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "help lists status command" {
    run bash -c "export HOME='${TEST_TEMP_DIR}'; export CLAWSPARK_DIR='${CLAWSPARK_DIR}'; bash '${CLAWSPARK_BIN}' help"
    [[ "$output" == *"status"* ]]
}

@test "help lists skills command" {
    run bash -c "export HOME='${TEST_TEMP_DIR}'; export CLAWSPARK_DIR='${CLAWSPARK_DIR}'; bash '${CLAWSPARK_BIN}' help"
    [[ "$output" == *"skills"* ]]
}

@test "help lists model command" {
    run bash -c "export HOME='${TEST_TEMP_DIR}'; export CLAWSPARK_DIR='${CLAWSPARK_DIR}'; bash '${CLAWSPARK_BIN}' help"
    [[ "$output" == *"model"* ]]
}

# ── Unknown command ───────────────────────────────────────────────────────────

@test "unknown command exits with error" {
    run bash -c "export HOME='${TEST_TEMP_DIR}'; export CLAWSPARK_DIR='${CLAWSPARK_DIR}'; bash '${CLAWSPARK_BIN}' __nonexistent_cmd__" 2>&1
    [ "$status" -eq 1 ]
}

@test "unknown command shows error message" {
    run bash -c "export HOME='${TEST_TEMP_DIR}'; export CLAWSPARK_DIR='${CLAWSPARK_DIR}'; bash '${CLAWSPARK_BIN}' __nonexistent_cmd__ 2>&1"
    [[ "$output" == *"Unknown command"* ]]
}

@test "unknown command still shows usage" {
    run bash -c "export HOME='${TEST_TEMP_DIR}'; export CLAWSPARK_DIR='${CLAWSPARK_DIR}'; bash '${CLAWSPARK_BIN}' __nonexistent_cmd__ 2>&1"
    [[ "$output" == *"Usage:"* ]]
}

# ── Command routing ──────────────────────────────────────────────────────────

@test "skills subcommand with no args exits with error" {
    run bash -c "export HOME='${TEST_TEMP_DIR}'; export CLAWSPARK_DIR='${CLAWSPARK_DIR}'; bash '${CLAWSPARK_BIN}' skills 2>&1"
    [ "$status" -eq 1 ]
}

@test "skills add without name exits with error" {
    run bash -c "export HOME='${TEST_TEMP_DIR}'; export CLAWSPARK_DIR='${CLAWSPARK_DIR}'; bash '${CLAWSPARK_BIN}' skills add 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* || "$output" == *"usage"* || "$output" == *"clawspark skills add"* ]]
}

@test "skills remove without name exits with error" {
    run bash -c "export HOME='${TEST_TEMP_DIR}'; export CLAWSPARK_DIR='${CLAWSPARK_DIR}'; bash '${CLAWSPARK_BIN}' skills remove 2>&1"
    [ "$status" -eq 1 ]
}

@test "model subcommand unknown exits with error" {
    run bash -c "export HOME='${TEST_TEMP_DIR}'; export CLAWSPARK_DIR='${CLAWSPARK_DIR}'; bash '${CLAWSPARK_BIN}' model bogus 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown model subcommand"* ]]
}

# ── Version constant ─────────────────────────────────────────────────────────

@test "CLAWSPARK_VERSION is defined in the script" {
    run bash -c "grep -q 'CLAWSPARK_VERSION=' '${CLAWSPARK_BIN}'"
    [ "$status" -eq 0 ]
}

@test "version format is semver" {
    run bash -c "export HOME='${TEST_TEMP_DIR}'; export CLAWSPARK_DIR='${CLAWSPARK_DIR}'; bash '${CLAWSPARK_BIN}' --version"
    [[ "$output" =~ v[0-9]+\.[0-9]+\.[0-9]+ ]]
}
