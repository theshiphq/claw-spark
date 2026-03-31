#!/usr/bin/env bats
# skills.bats -- Tests for skill YAML parsing and management.
# Sources real functions from clawspark CLI.

load test_helper

# Uses _parse_enabled_skills from common.sh (loaded in test_helper.bash)

# ── Load real skill helpers from clawspark CLI ────────────────────────────────
# We source the relevant functions but stub out npx/clawhub calls.

_load_skill_helpers() {
    export CLAWSPARK_LOG="${CLAWSPARK_DIR}/install.log"
    npx() { return 0; }
    export -f npx
    # Extract _skills_add and _skills_remove from the real clawspark CLI
    eval "$(sed -n '/^_skills_add()/,/^}/p' "${PROJECT_ROOT}/clawspark")"
    eval "$(sed -n '/^_skills_remove()/,/^}/p' "${PROJECT_ROOT}/clawspark")"
}

# ── Parsing tests ─────────────────────────────────────────────────────────────

@test "parse skills extracts 'name:' format entries" {
    result="$(_parse_enabled_skills "${CLAWSPARK_DIR}/skills.yaml")"
    [[ "$result" == *"test-skill-alpha"* ]]
    [[ "$result" == *"test-skill-beta"* ]]
}

@test "parse skills extracts simple '- slug' format entries" {
    result="$(_parse_enabled_skills "${CLAWSPARK_DIR}/skills.yaml")"
    [[ "$result" == *"simple-skill"* ]]
    [[ "$result" == *"another-simple"* ]]
}

@test "parse skills returns correct count" {
    result="$(_parse_enabled_skills "${CLAWSPARK_DIR}/skills.yaml")"
    count="$(echo "$result" | wc -l | tr -d ' ')"
    [ "$count" -eq 4 ]
}

@test "parse skills ignores comments" {
    cat > "${CLAWSPARK_DIR}/test-comments.yaml" <<'YAML'
skills:
  enabled:
    # This is a comment
    - name: real-skill
    # - name: commented-out
  custom: []
YAML
    result="$(_parse_enabled_skills "${CLAWSPARK_DIR}/test-comments.yaml")"
    [[ "$result" == *"real-skill"* ]]
    [[ "$result" != *"commented-out"* ]]
}

@test "parse skills ignores blank lines" {
    cat > "${CLAWSPARK_DIR}/test-blanks.yaml" <<'YAML'
skills:
  enabled:

    - name: skill-with-blanks

  custom: []
YAML
    result="$(_parse_enabled_skills "${CLAWSPARK_DIR}/test-blanks.yaml")"
    [[ "$result" == *"skill-with-blanks"* ]]
}

@test "parse skills stops at non-list key" {
    cat > "${CLAWSPARK_DIR}/test-stop.yaml" <<'YAML'
skills:
  enabled:
    - name: before-custom
  custom:
    - name: This should not appear
YAML
    result="$(_parse_enabled_skills "${CLAWSPARK_DIR}/test-stop.yaml")"
    [[ "$result" == *"before-custom"* ]]
    [[ "$result" != *"This should not"* ]]
}

@test "parse skills handles empty enabled section" {
    cat > "${CLAWSPARK_DIR}/test-empty.yaml" <<'YAML'
skills:
  enabled:
  custom: []
YAML
    result="$(_parse_enabled_skills "${CLAWSPARK_DIR}/test-empty.yaml")"
    [ -z "$result" ]
}

@test "parse skills skips description lines in name format" {
    cat > "${CLAWSPARK_DIR}/test-desc.yaml" <<'YAML'
skills:
  enabled:
    - name: has-desc
      description: This should not appear as a skill
    - name: another
  custom: []
YAML
    result="$(_parse_enabled_skills "${CLAWSPARK_DIR}/test-desc.yaml")"
    [[ "$result" == *"has-desc"* ]]
    [[ "$result" != *"This should not"* ]]
    count="$(echo "$result" | wc -l | tr -d ' ')"
    [ "$count" -eq 2 ]
}

# ── _skills_add (real function) ───────────────────────────────────────────────

@test "skills_add appends skill to YAML" {
    _load_skill_helpers
    _skills_add "new-test-skill" 2>/dev/null

    run cat "${CLAWSPARK_DIR}/skills.yaml"
    [[ "$output" == *"new-test-skill"* ]]
}

@test "skills_add does not duplicate existing skill" {
    _load_skill_helpers
    _skills_add "test-skill-alpha" 2>/dev/null

    local count
    count=$(grep -c "test-skill-alpha" "${CLAWSPARK_DIR}/skills.yaml")
    [ "$count" -eq 1 ]
}

# ── _skills_remove (real function) ────────────────────────────────────────────

@test "skills_remove deletes name-format entry" {
    _load_skill_helpers
    _skills_remove "test-skill-alpha" 2>/dev/null

    run cat "${CLAWSPARK_DIR}/skills.yaml"
    [[ "$output" != *"test-skill-alpha"* ]]
    [[ "$output" == *"test-skill-beta"* ]]
}

@test "skills_remove deletes simple-format entry" {
    _load_skill_helpers
    _skills_remove "simple-skill" 2>/dev/null

    run cat "${CLAWSPARK_DIR}/skills.yaml"
    [[ "$output" != *"simple-skill"* ]]
    [[ "$output" == *"another-simple"* ]]
}

# ── Pack listing ──────────────────────────────────────────────────────────────

@test "pack listing parses pack names" {
    local packs_file="${CLAWSPARK_DIR}/configs/skill-packs.yaml"

    run cat "${packs_file}"
    [[ "$output" == *"testpack"* ]]
    [[ "$output" == *"empty-pack"* ]]
}

@test "pack listing parses descriptions" {
    local packs_file="${CLAWSPARK_DIR}/configs/skill-packs.yaml"

    run cat "${packs_file}"
    [[ "$output" == *"A test pack"* ]]
    [[ "$output" == *"Empty pack"* ]]
}

@test "pack listing counts skills in testpack" {
    local packs_file="${CLAWSPARK_DIR}/configs/skill-packs.yaml"
    local in_testpack=false in_skills=false count=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*testpack: ]]; then
            in_testpack=true; continue
        fi
        if $in_testpack && [[ "$line" =~ ^[[:space:]]*skills: ]]; then
            in_skills=true; continue
        fi
        if $in_testpack && $in_skills && [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
            count=$((count + 1)); continue
        fi
        if $in_testpack && [[ "$line" =~ ^[[:space:]]{2}[a-zA-Z] ]] && [[ ! "$line" =~ skills: ]]; then
            break
        fi
    done < "${packs_file}"
    [ "$count" -eq 3 ]
}

@test "parse skills from real project skills.yaml" {
    if [ ! -f "${PROJECT_ROOT}/configs/skills.yaml" ]; then
        skip "Project skills.yaml not found"
    fi
    result="$(_parse_enabled_skills "${PROJECT_ROOT}/configs/skills.yaml")"
    [ -n "$result" ]
    count="$(echo "$result" | wc -l | tr -d ' ')"
    [ "$count" -gt 0 ]
}
