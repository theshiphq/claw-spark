#!/usr/bin/env bash
# run.sh -- Run all clawspark bats tests.
# Installs bats-core to a temp dir if not already available.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

BATS_BIN=""

if command -v bats &>/dev/null; then
    BATS_BIN="bats"
elif [ -x "${SCRIPT_DIR}/.bats/bin/bats" ]; then
    BATS_BIN="${SCRIPT_DIR}/.bats/bin/bats"
else
    echo "bats not found. Installing bats-core locally..."
    BATS_TMP="${SCRIPT_DIR}/.bats"
    CLONE_ERR=$(mktemp)
    if ! git clone --depth 1 https://github.com/bats-core/bats-core.git "${BATS_TMP}" 2>"${CLONE_ERR}"; then
        echo "ERROR: Failed to clone bats-core:" >&2
        cat "${CLONE_ERR}" >&2
        rm -f "${CLONE_ERR}"
        exit 1
    fi
    rm -f "${CLONE_ERR}"
    BATS_BIN="${BATS_TMP}/bin/bats"
    if [ ! -x "${BATS_BIN}" ]; then
        echo "ERROR: bats binary not found after clone." >&2
        exit 1
    fi
    echo "bats-core installed to ${BATS_TMP}"
fi

echo ""
echo "Running clawspark tests..."
echo "─────────────────────────────────────────"
echo ""

FAILED=0

for test_file in "${SCRIPT_DIR}"/*.bats; do
    [ -f "${test_file}" ] || continue
    name="$(basename "${test_file}")"
    echo "==> ${name}"
    if "${BATS_BIN}" "${test_file}"; then
        echo ""
    else
        FAILED=$((FAILED + 1))
        echo ""
    fi
done

echo "─────────────────────────────────────────"
if [ "${FAILED}" -eq 0 ]; then
    echo "All test suites passed."
else
    echo "${FAILED} test suite(s) had failures."
    exit 1
fi
