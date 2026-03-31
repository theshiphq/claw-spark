#!/usr/bin/env bats
# common.bats -- Tests for lib/common.sh functions.

load test_helper

# ── to_lower ──────────────────────────────────────────────────────────────────

@test "to_lower converts uppercase to lowercase" {
    result="$(to_lower "HELLO")"
    [ "$result" = "hello" ]
}

@test "to_lower leaves lowercase unchanged" {
    result="$(to_lower "world")"
    [ "$result" = "world" ]
}

@test "to_lower handles mixed case" {
    result="$(to_lower "HeLLo WoRLd")"
    [ "$result" = "hello world" ]
}

@test "to_lower handles empty string" {
    result="$(to_lower "")"
    [ "$result" = "" ]
}

@test "to_lower handles numbers and symbols" {
    result="$(to_lower "ABC-123_DEF")"
    [ "$result" = "abc-123_def" ]
}

# ── check_command ─────────────────────────────────────────────────────────────

@test "check_command returns 0 for existing command (bash)" {
    run check_command bash
    [ "$status" -eq 0 ]
}

@test "check_command returns 0 for existing command (ls)" {
    run check_command ls
    [ "$status" -eq 0 ]
}

@test "check_command returns 1 for nonexistent command" {
    run check_command __clawspark_nonexistent_binary_xyz__
    [ "$status" -eq 1 ]
}

@test "check_command returns 1 for empty argument" {
    run check_command ""
    [ "$status" -eq 1 ]
}

# ── Color variables ──────────────────────────────────────────────────────────

@test "color variables are defined" {
    [ -n "$RED" ]
    [ -n "$GREEN" ]
    [ -n "$YELLOW" ]
    [ -n "$BLUE" ]
    [ -n "$CYAN" ]
    [ -n "$BOLD" ]
    [ -n "$RESET" ]
}

# ── _ts ───────────────────────────────────────────────────────────────────────

@test "_ts returns a valid HH:MM:SS timestamp" {
    result="$(_ts)"
    [[ "$result" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]
}

@test "_ts output reflects current time" {
    local ref
    ref=$(date '+%H')
    result="$(_ts)"
    [[ "${result%%:*}" == "${ref}" ]]
}

# ── log_info ──────────────────────────────────────────────────────────────────

@test "log_info writes to stdout" {
    run log_info "test message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test message"* ]]
}

@test "log_info includes timestamp" {
    run log_info "hello"
    [[ "$output" =~ \[[0-9]{2}:[0-9]{2}:[0-9]{2}\] ]]
}

@test "log_info writes to log file" {
    log_info "file log test"
    [ -f "${CLAWSPARK_LOG}" ]
    run cat "${CLAWSPARK_LOG}"
    [[ "$output" == *"INFO"* ]]
    [[ "$output" == *"file log test"* ]]
}

# ── log_warn ──────────────────────────────────────────────────────────────────

@test "log_warn writes WARNING to stderr" {
    run bash -c 'source "'"${CLAWSPARK_DIR}/lib/common.sh"'" && log_warn "something wrong" 2>&1 1>/dev/null'
    [[ "$output" == *"WARNING"* ]]
    [[ "$output" == *"something wrong"* ]]
}

@test "log_warn writes to log file with WARN level" {
    log_warn "warn file test" 2>/dev/null
    run cat "${CLAWSPARK_LOG}"
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"warn file test"* ]]
}

# ── log_error ─────────────────────────────────────────────────────────────────

@test "log_error writes ERROR to stderr" {
    run bash -c 'source "'"${CLAWSPARK_DIR}/lib/common.sh"'" && log_error "bad thing" 2>&1 1>/dev/null'
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"bad thing"* ]]
}

@test "log_error writes to log file with ERROR level" {
    log_error "error file test" 2>/dev/null
    run cat "${CLAWSPARK_LOG}"
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"error file test"* ]]
}

# ── log_success ───────────────────────────────────────────────────────────────

@test "log_success writes OK to stdout" {
    run log_success "all good"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
    [[ "$output" == *"all good"* ]]
}

@test "log_success writes to log file with OK level" {
    log_success "success file test"
    run cat "${CLAWSPARK_LOG}"
    [[ "$output" == *"OK"* ]]
    [[ "$output" == *"success file test"* ]]
}

# ── _log_to_file ──────────────────────────────────────────────────────────────

@test "_log_to_file creates log with timestamp and level" {
    _log_to_file "DEBUG" "custom level test"
    run cat "${CLAWSPARK_LOG}"
    [[ "$output" == *"DEBUG"* ]]
    [[ "$output" == *"custom level test"* ]]
    [[ "$output" =~ \[[0-9]{4}-[0-9]{2}-[0-9]{2} ]]
}

@test "_log_to_file does not fail when CLAWSPARK_DIR is missing" {
    local old_dir="${CLAWSPARK_DIR}"
    CLAWSPARK_DIR="/nonexistent/path"
    run _log_to_file "INFO" "should not fail"
    [ "$status" -eq 0 ]
    CLAWSPARK_DIR="${old_dir}"
}

# ── hr ────────────────────────────────────────────────────────────────────────

@test "hr produces output" {
    run hr
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

# ── print_box ─────────────────────────────────────────────────────────────────

@test "print_box renders box borders" {
    run print_box "hello" "world"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello"* ]]
    [[ "$output" == *"world"* ]]
}

# ── CLAWSPARK_DIR paths ──────────────────────────────────────────────────────

@test "CLAWSPARK_DIR is set to temp directory" {
    [[ "$CLAWSPARK_DIR" == *".clawspark" ]]
    [ -d "$CLAWSPARK_DIR" ]
}

@test "CLAWSPARK_LOG is under CLAWSPARK_DIR" {
    [[ "$CLAWSPARK_LOG" == "${CLAWSPARK_DIR}/install.log" ]]
}
