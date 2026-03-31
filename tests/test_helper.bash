#!/usr/bin/env bash
# test_helper.bash -- Setup/teardown for clawspark bats tests.

_find_project_root() {
    local dir="${BATS_TEST_DIRNAME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
    local candidate="${dir}/.."
    if [ -f "${candidate}/clawspark" ]; then
        (cd "${candidate}" && pwd)
        return
    fi
    for try in "/tmp/claw-spark" "/private/tmp/claw-spark"; do
        if [ -f "${try}/clawspark" ]; then
            echo "${try}"
            return
        fi
    done
    echo "${candidate}"
}
PROJECT_ROOT="$(_find_project_root)"

# Cross-platform stat permission helper (macOS vs Linux)
_get_permissions() {
    stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null || echo "unknown"
}

setup() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export CLAWSPARK_DIR="${TEST_TEMP_DIR}/.clawspark"
    export CLAWSPARK_LOG="${CLAWSPARK_DIR}/install.log"
    export CLAWSPARK_DEFAULTS="true"
    export HOME="${TEST_TEMP_DIR}"

    mkdir -p "${CLAWSPARK_DIR}/lib"
    mkdir -p "${CLAWSPARK_DIR}/configs"

    if [[ ! -f "${PROJECT_ROOT}/lib/common.sh" ]]; then
        echo "ERROR: lib/common.sh not found at ${PROJECT_ROOT}" >&2
        return 1
    fi
    cp "${PROJECT_ROOT}/lib/common.sh" "${CLAWSPARK_DIR}/lib/common.sh"

    cat > "${CLAWSPARK_DIR}/configs/skills.yaml" <<'YAML'
skills:
  enabled:
    - name: test-skill-alpha
      description: First test skill
    - name: test-skill-beta
      description: Second test skill
    - simple-skill
    - another-simple
  custom: []
YAML

    cp "${CLAWSPARK_DIR}/configs/skills.yaml" "${CLAWSPARK_DIR}/skills.yaml"

    cat > "${CLAWSPARK_DIR}/configs/skill-packs.yaml" <<'YAML'
packs:
  testpack:
    description: "A test pack"
    skills:
      - skill-one
      - skill-two
      - skill-three
  empty-pack:
    description: "Empty pack"
    skills: []
YAML

    source "${CLAWSPARK_DIR}/lib/common.sh"
}

teardown() {
    if [[ -n "${TEST_TEMP_DIR:-}" && -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}
