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

    # ── Parse enabled skills (simple YAML parser) ──────────────────────────
    # Supports two formats:
    #   Format A (simple):   - skill-slug
    #   Format B (detailed): - name: skill-slug
    local -a skills=()
    local in_enabled=false

    while IFS= read -r line; do
        # Skip comments and blank lines
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Detect the "enabled:" section (may be nested under "skills:")
        if [[ "${line}" =~ enabled:[[:space:]]*$ ]]; then
            in_enabled=true
            continue
        fi

        # A key at the same or higher indentation level ends the section
        # (e.g. "custom:", another top-level key)
        if ${in_enabled} && [[ "${line}" =~ ^[[:space:]]{0,3}[a-zA-Z] ]] && [[ ! "${line}" =~ ^[[:space:]]*- ]]; then
            in_enabled=false
            continue
        fi

        # Format B: "- name: skill-slug"
        if ${in_enabled} && [[ "${line}" =~ ^[[:space:]]*-[[:space:]]+name:[[:space:]]+(.*) ]]; then
            local slug="${BASH_REMATCH[1]}"
            slug="${slug## }"
            slug="${slug%% }"
            skills+=("${slug}")
            continue
        fi

        # Format A: "- skill-slug"
        if ${in_enabled} && [[ "${line}" =~ ^[[:space:]]*-[[:space:]]+(.*) ]]; then
            local slug="${BASH_REMATCH[1]}"
            slug="${slug## }"
            slug="${slug%% }"
            # Skip if this is a YAML key (e.g. "name: ...")
            [[ "${slug}" =~ ^[a-zA-Z]+: ]] && continue
            skills+=("${slug}")
        fi
    done < "${skills_file}"

    if [[ ${#skills[@]} -eq 0 ]]; then
        log_warn "No skills found under 'enabled:' in ${skills_file}."
        return 0
    fi

    log_info "Found ${#skills[@]} skill(s) to install."

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
