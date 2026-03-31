#!/usr/bin/env bash
# lib/setup-skills.sh — Reads skills.yaml and installs each enabled skill via clawhub.
set -euo pipefail

setup_skills() {
    log_info "Installing OpenClaw skills..."
    hr

    # ── Locate skills.yaml ──────────────────────────────────────────────────
    local skills_file=""
    local search_paths=(
        "${CLAWSPARK_DIR}/skills.yaml"
        "${SCRIPT_DIR:-/opt/clawspark}/configs/skills.yaml"
    )

    for candidate in "${search_paths[@]}"; do
        if [[ -f "${candidate}" ]]; then
            skills_file="${candidate}"
            break
        fi
    done

    if [[ -z "${skills_file}" ]]; then
        log_warn "No skills.yaml found — skipping skill installation."
        return 0
    fi

    log_info "Using skills config: ${skills_file}"

    # Copy to CLAWSPARK_DIR if not already there
    if [[ "${skills_file}" != "${CLAWSPARK_DIR}/skills.yaml" ]]; then
        cp "${skills_file}" "${CLAWSPARK_DIR}/skills.yaml"
    fi

    local -a skills=()
    while IFS= read -r slug; do
        skills+=("${slug}")
    done < <(_parse_enabled_skills "${skills_file}")

    if [[ ${#skills[@]} -eq 0 ]]; then
        log_warn "No skills found under 'enabled:' in ${skills_file}."
        return 0
    fi

    log_info "Found ${#skills[@]} skill(s) to install."

    # ── Fix npm cache permissions (root-owned ~/.npm from sudo npm) ─────────
    _fix_npm_cache_perms

    # ── Install each skill ──────────────────────────────────────────────────
    local installed=0
    local failed=0

    local skill_timeout=120  # 2 minutes max per skill

    for skill in "${skills[@]}"; do
        printf '  %s→%s Installing %s%s%s ... ' "${CYAN}" "${RESET}" "${BOLD}" "${skill}" "${RESET}"
        if timeout "${skill_timeout}" npx --yes clawhub@latest install --force "${skill}" >> "${CLAWSPARK_LOG}" 2>&1; then
            printf '%s✓%s\n' "${GREEN}" "${RESET}"
            installed=$(( installed + 1 ))
        else
            local ec=$?
            if [[ ${ec} -eq 124 ]]; then
                printf '%s✗ (timed out after %ds, skipping)%s\n' "${YELLOW}" "${skill_timeout}" "${RESET}"
            else
                printf '%s✗ (failed, continuing)%s\n' "${YELLOW}" "${RESET}"
            fi
            log_warn "Skill '${skill}' failed to install — see ${CLAWSPARK_LOG}"
            failed=$(( failed + 1 ))
        fi
    done

    printf '\n'
    log_success "Skills installed: ${installed} succeeded, ${failed} failed."

    # ── Install essential community skills (web search, research) ─────────
    _install_community_skills
}

# ── Community skills that don't need API keys ─────────────────────────────
_install_community_skills() {
    log_info "Installing community web search skills..."
    local -a community_skills=(
        "ddg-web-search"
        "deep-research-pro"
        "local-web-search-skill"
    )
    for skill in "${community_skills[@]}"; do
        printf '  %s->%s Installing %s%s%s ... ' "${CYAN}" "${RESET}" "${BOLD}" "${skill}" "${RESET}"
        if timeout 120 npx --yes clawhub@latest install --force "${skill}" >> "${CLAWSPARK_LOG}" 2>&1; then
            printf '%sOK%s\n' "${GREEN}" "${RESET}"
        else
            printf '%sskipped%s\n' "${YELLOW}" "${RESET}"
        fi
    done
    log_success "Community skills installed (web search, deep research)."
}

# ── Fix root-owned npm cache (common after sudo npm install -g) ───────────
_fix_npm_cache_perms() {
    local npm_cache="${HOME}/.npm"
    if [[ -d "${npm_cache}" ]]; then
        # Check if any files are owned by root (uid 0)
        local root_files
        root_files=$(find "${npm_cache}" -maxdepth 2 -uid 0 2>/dev/null | head -1)
        if [[ -n "${root_files}" ]]; then
            log_info "Fixing npm cache permissions (root-owned files in ~/.npm)..."
            sudo chown -R "$(id -u):$(id -g)" "${npm_cache}" 2>/dev/null || {
                log_warn "Could not fix ~/.npm permissions. Skills may fail to install."
            }
        fi
    fi
}
