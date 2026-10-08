#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="scripts/gce-arm-bootstrap.sh"

echo "Checking bash syntax for ${SCRIPT_PATH}..."
bash -n "${SCRIPT_PATH}"

echo "Checking required keywords in ${SCRIPT_PATH}..."
grep -q "installdependencies.sh" "${SCRIPT_PATH}" || { echo "FAIL: Missing installdependencies.sh"; exit 1; }
grep -q "set -euo pipefail" "${SCRIPT_PATH}" || { echo "FAIL: Missing set -euo pipefail"; exit 1; }
grep -q "2.338.0" "${SCRIPT_PATH}" || { echo "FAIL: Expected modern runner version >= 2.338.0"; exit 1; }
grep -q "sleep 3600" "${SCRIPT_PATH}" || { echo "FAIL: Expected 60-minute watchdog"; exit 1; }

echo "PASS: Bootstrap script syntax and safety checks passed."
