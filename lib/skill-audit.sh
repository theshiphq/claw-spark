#!/usr/bin/env bash
set -euo pipefail

SKILLS_DIR="${HOME}/.openclaw/skills"
CLAWSPARK_DIR="${CLAWSPARK_DIR:-${HOME}/.clawspark}"
HASH_FILE="${CLAWSPARK_DIR}/skill-hashes.json"
AUDIT_REPORT="${CLAWSPARK_DIR}/audit-report.txt"

ALLOWLIST=(
    "local-whisper"
    "self-improvement"
    "memory-setup"
    "whatsapp-voice-chat-integration-open-source"
    "deep-research-pro"
    "agent-browser"
    "second-brain"
    "proactive-agent"
    "ddg-web-search"
    "local-web-search-skill"
)

_NETWORK_PATTERNS=(
    'fetch('
    'axios'
    'http\.request'
    'net\.connect'
    'XMLHttpRequest'
    'WebSocket('
)

_CREDENTIAL_PATTERNS=(
    '~/\.ssh'
    '\$HOME/\.ssh'
    '~/\.aws'
    '\$HOME/\.aws'
    '~/\.env'
    '/etc/passwd'
    '/etc/shadow'
    'process\.env\.'
    'os\.environ'
    'keychain'
    'credential'
)

_OBFUSCATION_PATTERNS=(
    'eval('
    'Function('
    'atob('
    'Buffer\.from.*base64'
    'exec('
    '__import__'
    'compile('
)

_EXFILTRATION_PATTERNS=(
    'FormData'
    'encodeURIComponent.*token'
    'btoa('
)

_FILESYSTEM_PATTERNS=(
    '\.\./\.\.'
    '\.\.\\/\.\.\\'
)

_PROCESS_PATTERNS=(
    'child_process'
    'subprocess'
    'os\.system'
    'os\.popen'
)

_is_allowlisted() {
    local name="$1"
    for allowed in "${ALLOWLIST[@]}"; do
        if [[ "${name}" == "${allowed}" ]]; then
            return 0
        fi
    done
    return 1
}

_compute_skill_hash() {
    local skill_dir="$1"
    if check_command shasum; then
        find "${skill_dir}" -type f \( -name '*.js' -o -name '*.ts' -o -name '*.py' -o -name '*.sh' -o -name '*.json' \) \
            -exec shasum -a 256 {} \; 2>/dev/null | sort | shasum -a 256 | cut -d' ' -f1
    elif check_command sha256sum; then
        find "${skill_dir}" -type f \( -name '*.js' -o -name '*.ts' -o -name '*.py' -o -name '*.sh' -o -name '*.json' \) \
            -exec sha256sum {} \; 2>/dev/null | sort | sha256sum | cut -d' ' -f1
    else
        echo "no-hash-tool"
    fi
}

_load_hashes() {
    if [[ -f "${HASH_FILE}" ]]; then
        cat "${HASH_FILE}"
    else
        echo "{}"
    fi
}

_save_hashes() {
    local json="$1"
    echo "${json}" > "${HASH_FILE}"
    chmod 600 "${HASH_FILE}"
}

_escape_sed() {
    printf '%s' "$1" | sed 's/[&/\]/\\&/g'
}

_get_stored_hash() {
    local json="$1"
    local skill="$2"
    if check_command jq; then
        echo "${json}" | jq -r --arg k "${skill}" '.[$k] // empty' 2>/dev/null || echo ""
    else
        local escaped
        escaped=$(_escape_sed "${skill}")
        echo "${json}" | grep -o "\"${escaped}\":\"[a-f0-9]*\"" | cut -d'"' -f4 || echo ""
    fi
}

_set_hash_entry() {
    local json="$1"
    local skill="$2"
    local hash="$3"

    if check_command jq; then
        echo "${json}" | jq --arg k "${skill}" --arg v "${hash}" '.[$k] = $v' 2>/dev/null
        return
    fi

    local escaped_skill
    escaped_skill=$(_escape_sed "${skill}")

    if [[ "${json}" == "{}" ]]; then
        echo "{\"${skill}\":\"${hash}\"}"
        return
    fi

    if echo "${json}" | grep -q "\"${escaped_skill}\":"; then
        echo "${json}" | sed "s/\"${escaped_skill}\":\"[a-f0-9]*\"/\"${escaped_skill}\":\"${hash}\"/"
    else
        echo "${json}" | sed "s/}$/,\"${escaped_skill}\":\"${hash}\"}/"
    fi
}

_scan_patterns() {
    local skill_dir="$1"
    local -a findings=()

    local source_file_list
    source_file_list=$(mktemp)
    find "${skill_dir}" -type f \( -name '*.js' -o -name '*.ts' -o -name '*.py' -o -name '*.sh' \) -print0 2>/dev/null > "${source_file_list}" || true

    if [[ ! -s "${source_file_list}" ]]; then
        rm -f "${source_file_list}"
        echo ""
        return
    fi

    local -a _categories=("network" "credential" "obfuscation" "exfiltration" "path_traversal" "process_spawn")
    local -a _arrays=("_NETWORK_PATTERNS" "_CREDENTIAL_PATTERNS" "_OBFUSCATION_PATTERNS" "_EXFILTRATION_PATTERNS" "_FILESYSTEM_PATTERNS" "_PROCESS_PATTERNS")

    local i pattern category arr_name
    for i in $(seq 0 $(( ${#_categories[@]} - 1 ))); do
        category="${_categories[$i]}"
        arr_name="${_arrays[$i]}"
        eval "local -a _pats=(\"\${${arr_name}[@]}\")"
        for pattern in "${_pats[@]}"; do
            if xargs -0 grep -l "${pattern}" < "${source_file_list}" 2>/dev/null | head -1 | grep -q .; then
                findings+=("${category}:${pattern}")
            fi
        done
    done

    rm -f "${source_file_list}"

    local IFS="|"
    echo "${findings[*]:-}"
}

_dir_size_human() {
    du -sh "$1" 2>/dev/null | cut -f1 | tr -d ' '
}

audit_skills() {
    log_info "Running skill security audit..."
    hr

    mkdir -p "${CLAWSPARK_DIR}"

    if [[ ! -d "${SKILLS_DIR}" ]]; then
        log_warn "Skills directory not found: ${SKILLS_DIR}"
        log_info "No skills installed. Nothing to audit."
        return 0
    fi

    local -a skill_dirs=()
    for d in "${SKILLS_DIR}"/*/; do
        [[ -d "${d}" ]] && skill_dirs+=("${d}")
    done

    if [[ ${#skill_dirs[@]} -eq 0 ]]; then
        log_info "No skills installed. Nothing to audit."
        return 0
    fi

    local total_pass=0
    local total_warn=0
    local total_fail=0
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local hashes
    hashes=$(_load_hashes)

    local col_name=30
    local col_status=8
    local separator
    separator=$(printf '%90s' '' | tr ' ' '─')
    local header_line
    header_line=$(printf '%-*s %-*s %s' ${col_name} "SKILL NAME" ${col_status} "STATUS" "FINDINGS")

    printf '\n  %s%s%s\n' "${BOLD}" "${header_line}" "${RESET}"
    printf '  %s%s%s\n' "${BLUE}" "${separator}" "${RESET}"

    local report_lines=()
    report_lines+=("ClawSpark Skill Audit Report")
    report_lines+=("Timestamp: ${timestamp}")
    report_lines+=("Skills directory: ${SKILLS_DIR}")
    report_lines+=("${separator}")
    report_lines+=("${header_line}")
    report_lines+=("${separator}")

    for skill_path in "${skill_dirs[@]}"; do
        local skill_name
        skill_name=$(basename "${skill_path}")
        local size
        size=$(_dir_size_human "${skill_path}")

        local -a issues=()
        local status="PASS"
        local status_color="${GREEN}"

        if [[ ! -f "${skill_path}/SKILL.md" ]] && [[ ! -f "${skill_path}/skill.md" ]]; then
            issues+=("missing SKILL.md")
            if [[ "${status}" != "FAIL" ]]; then
                status="WARN"
                status_color="${YELLOW}"
            fi
        fi

        if ! _is_allowlisted "${skill_name}"; then
            issues+=("unverified (not in allowlist)")
            if [[ "${status}" != "FAIL" ]]; then
                status="WARN"
                status_color="${YELLOW}"
            fi
        fi

        local scan_result
        scan_result=$(_scan_patterns "${skill_path}")

        if [[ -n "${scan_result}" ]]; then
            local IFS='|'
            local -a pattern_hits=()
            read -ra pattern_hits <<< "${scan_result}"

            local has_critical=false
            local finding
            for finding in "${pattern_hits[@]}"; do
                local category="${finding%%:*}"
                local detail="${finding#*:}"
                issues+=("${category}: ${detail}")
                case "${category}" in
                    credential|exfiltration|obfuscation|process_spawn)
                        has_critical=true
                        ;;
                esac
            done

            if ${has_critical}; then
                status="FAIL"
                status_color="${RED}"
            elif [[ "${status}" != "FAIL" ]]; then
                status="WARN"
                status_color="${YELLOW}"
            fi
        fi

        local current_hash
        current_hash=$(_compute_skill_hash "${skill_path}")
        local stored_hash
        stored_hash=$(_get_stored_hash "${hashes}" "${skill_name}")

        if [[ -n "${stored_hash}" && "${stored_hash}" != "${current_hash}" && "${stored_hash}" != "no-hash-tool" && "${current_hash}" != "no-hash-tool" ]]; then
            issues+=("files changed since last audit")
            if [[ "${status}" == "PASS" ]]; then
                status="WARN"
                status_color="${YELLOW}"
            fi
        fi

        hashes=$(_set_hash_entry "${hashes}" "${skill_name}" "${current_hash}")

        local findings_str
        if [[ ${#issues[@]} -eq 0 ]]; then
            findings_str="clean (${size})"
        else
            local IFS="; "
            findings_str="${issues[*]} (${size})"
        fi

        printf '  %-*s %s%-*s%s %s\n' \
            ${col_name} "${skill_name}" \
            "${status_color}" ${col_status} "${status}" "${RESET}" \
            "${findings_str}"

        report_lines+=("$(printf '%-*s %-*s %s' ${col_name} "${skill_name}" ${col_status} "${status}" "${findings_str}")")

        case "${status}" in
            PASS) total_pass=$(( total_pass + 1 )) ;;
            WARN) total_warn=$(( total_warn + 1 )) ;;
            FAIL) total_fail=$(( total_fail + 1 )) ;;
        esac
    done

    _save_hashes "${hashes}"

    printf '  %s%s%s\n\n' "${BLUE}" "${separator}" "${RESET}"

    report_lines+=("${separator}")
    report_lines+=("")

    local summary
    summary="Total: ${GREEN}${total_pass} PASS${RESET}, ${YELLOW}${total_warn} WARN${RESET}, ${RED}${total_fail} FAIL${RESET}"
    printf '  %s\n\n' "${summary}"

    local summary_plain="Total: ${total_pass} PASS, ${total_warn} WARN, ${total_fail} FAIL"
    report_lines+=("${summary_plain}")

    {
        for line in "${report_lines[@]}"; do
            echo "${line}"
        done
    } > "${AUDIT_REPORT}"
    chmod 600 "${AUDIT_REPORT}"

    if (( total_fail > 0 )); then
        log_error "${total_fail} skill(s) flagged as FAIL — review immediately."
        print_box \
            "${RED}${BOLD}Security Alert${RESET}" \
            "" \
            "${total_fail} skill(s) contain suspicious patterns." \
            "Run 'clawspark skills remove <name>' for any untrusted skill." \
            "Report: ${AUDIT_REPORT}"
    elif (( total_warn > 0 )); then
        log_warn "${total_warn} skill(s) flagged as WARN — review recommended."
    else
        log_success "All ${total_pass} skill(s) passed security audit."
    fi

    log_info "Audit report saved to ${AUDIT_REPORT}"
    log_info "Hash database saved to ${HASH_FILE}"
}

_quick_skill_check() {
    local skill_path="$1"
    local skill_name
    skill_name=$(basename "${skill_path}")

    if [[ ! -d "${skill_path}" ]]; then
        log_error "Skill directory not found: ${skill_path}"
        return 1
    fi

    log_info "Quick security check: ${skill_name}"

    local -a issues=()
    local status="PASS"

    if [[ ! -f "${skill_path}/SKILL.md" ]] && [[ ! -f "${skill_path}/skill.md" ]]; then
        issues+=("missing SKILL.md")
        status="WARN"
    fi

    if ! _is_allowlisted "${skill_name}"; then
        issues+=("not in curated allowlist")
        status="WARN"
    fi

    local scan_result
    scan_result=$(_scan_patterns "${skill_path}")

    if [[ -n "${scan_result}" ]]; then
        local IFS='|'
        local -a pattern_hits=()
        read -ra pattern_hits <<< "${scan_result}"

        local finding
        for finding in "${pattern_hits[@]}"; do
            local category="${finding%%:*}"
            local detail="${finding#*:}"
            issues+=("${category}: ${detail}")
            case "${category}" in
                credential|exfiltration|obfuscation|process_spawn)
                    status="FAIL"
                    ;;
                *)
                    if [[ "${status}" != "FAIL" ]]; then
                        status="WARN"
                    fi
                    ;;
            esac
        done
    fi

    case "${status}" in
        PASS)
            log_success "Skill '${skill_name}' passed pre-install check."
            return 0
            ;;
        WARN)
            log_warn "Skill '${skill_name}' has warnings:"
            for issue in "${issues[@]}"; do
                printf '  %s⚠%s  %s\n' "${YELLOW}" "${RESET}" "${issue}"
            done
            return 0
            ;;
        FAIL)
            log_error "Skill '${skill_name}' BLOCKED — suspicious patterns detected:"
            for issue in "${issues[@]}"; do
                printf '  %s✗%s  %s\n' "${RED}" "${RESET}" "${issue}"
            done
            printf '\n'
            print_box \
                "${RED}${BOLD}Installation Blocked${RESET}" \
                "" \
                "Skill '${skill_name}' contains patterns associated with malware." \
                "341 malicious skills were found on ClawHub (Atomic Stealer, data theft)." \
                "Use --force to override this check at your own risk."
            return 1
            ;;
    esac
}
