# Fix GCE Ephemeral ARM Runner Bootstrap & Workflow Hanging Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix premature instance shutdown and missing dependencies in GCE ARM64 runner startup, preventing GitHub Actions release workflows from hanging in queued state indefinitely.

**Architecture:** Update `scripts/gce-arm-bootstrap.sh` to extract the GitHub Actions runner as root, execute `./bin/installdependencies.sh` (supporting Ubuntu 24.04), run runner registration and execution under strict subshell error traps (`set -euo pipefail`), and only invoke `poweroff` on successful job completion. Enhance `.github/workflows/release.yml` with serial port logging, an increased `--max-run-duration=60m`, and a readiness polling loop that validates runner registration within 3 minutes before dispatching downstream jobs.

**Tech Stack:** Bash, GitHub Actions Workflow Syntax, Google Cloud Compute Engine (GCE), GitHub REST API (`gh`/`curl`/`jq`).

**Spec:** Findings from systematic debugging of run `37590819457` on `jimmystewpot/vector-optimised`.

## Global Constraints
- Do not break existing x86_64 or ARM64 build pipelines.
- Runner VM must remain strictly ephemeral and single-job (`--ephemeral`).
- Cloud compute cost must remain bounded: VMs must always be terminated upon job completion or failure (enforced by GCE `--max-run-duration`).
- Preserved debugging logs: Serial port logging must be enabled on GCE VM instances to capture startup script failures in GCP Cloud Logging.

## Review Focus
1. **Runner configuration failure:** `./config.sh` fails due to network or invalid token; script must exit non-zero and NOT call `poweroff` immediately, preserving serial console logs before GCE auto-deletes the VM.
2. **Missing runner dependencies on Ubuntu 24.04:** `installdependencies.sh` must be executed from runner version `>= 2.338.0` containing `liblttng-ust1t64`, `libssl3`, and `libicu74` mappings.
3. **Runner registration timeout:** If the VM or startup script fails, `launch-arm-runner` must detect runner absence within 3 minutes and fail the job rather than letting `build-arm` wait in queued state for 24 hours.
4. **Premature VM deletion during compilation:** GCE `--max-run-duration` must be 60m (matching workflow `timeout-minutes: 60`), and the script watchdog timer must be 3600s (60m).
5. **Clean teardown on launch failure:** `teardown-arm-runner` must cleanly tear down any created VM even if `launch-arm-runner` fails during runner registration polling.

---

### Task 1: Fix `scripts/gce-arm-bootstrap.sh` Dependency Installation and Error Trapping

**Files:**
- Modify: `scripts/gce-arm-bootstrap.sh`
- Test: `tests/test_bootstrap_syntax.sh`

**Interfaces:**
- Consumes: GCE instance metadata attributes (`github-repo`, `runner-token`, `runner-labels`).
- Produces: Correctly configured ephemeral GitHub Actions runner running on ARM64 Ubuntu 24.04.

- [ ] **Step 1: Write a validation script for `gce-arm-bootstrap.sh`**

Create `tests/test_bootstrap_syntax.sh`:
```bash
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
```
Make executable: `chmod +x tests/test_bootstrap_syntax.sh`

- [ ] **Step 2: Run validation script to verify it fails**

Run: `./tests/test_bootstrap_syntax.sh`
Expected: FAIL with "Missing installdependencies.sh"

- [ ] **Step 3: Update `scripts/gce-arm-bootstrap.sh`**

Implement fixes in `scripts/gce-arm-bootstrap.sh`:
1. Update runner version to `2.338.0`.
2. Update watchdog timer to 3600s (`(sleep 3600 && poweroff) &`).
3. Download and extract the runner package to `/home/runner/actions-runner` as root.
4. Execute `/home/runner/actions-runner/bin/installdependencies.sh` as root before running the runner.
5. Set ownership of `/home/runner/actions-runner` to `runner:runner`.
6. Run `./config.sh` and `./run.sh` under `su - runner -c "..."` with `set -euo pipefail`.
7. Check the exit status of `su - runner`:
   - If success: run `poweroff` to halt compute billing.
   - If failure: log error message to stderr (which streams to serial console) and do NOT call `poweroff` immediately, allowing GCE max-run-duration to clean up while logs remain accessible.

- [ ] **Step 4: Run validation script to verify it passes**

Run: `./tests/test_bootstrap_syntax.sh`
Expected: PASS

- [ ] **Step 5: Commit changes**

```bash
git add scripts/gce-arm-bootstrap.sh tests/test_bootstrap_syntax.sh
git commit -m "fix(arm-runner): install runner dependencies and harden error handling in bootstrap script"
```

---

### Task 2: Enhance `.github/workflows/release.yml` with Serial Logging, 60m Max Duration, and Runner Readiness Verification

**Files:**
- Modify: `.github/workflows/release.yml:138-175`, `.github/workflows/release.yml:230-245`
- Test: `tests/test_workflow_syntax.py`

**Interfaces:**
- Consumes: GitHub App runner registration token and GCE instance creation.
- Produces: Validated runner registration in GitHub Actions before exiting `launch-arm-runner`.

- [ ] **Step 1: Write a workflow validation script**

Create `tests/test_workflow_syntax.py`:
```python
#!/usr/bin/env python3
import sys

with open(".github/workflows/release.yml", "r") as f:
    content = f.read()

checks = [
    ("serial-port-logging-enable=true", "Missing serial port logging in GCE metadata"),
    ("max-run-duration=60m", "Expected max-run-duration=60m for long compilation"),
    ("actions/runners", "Missing runner readiness polling loop in launch-arm-runner"),
]

failed = False
for needle, err_msg in checks:
    if needle not in content:
        print(f"FAIL: {err_msg}", file=sys.stderr)
        failed = True

if failed:
    sys.exit(1)

print("PASS: release.yml validation checks passed.")
```

- [ ] **Step 2: Run validation script to verify it fails**

Run: `python3 tests/test_workflow_syntax.py`
Expected: FAIL with missing configuration checks.

- [ ] **Step 3: Update `.github/workflows/release.yml`**

1. In `launch-arm-runner`:
   - In `gcloud compute instances create`:
     - Change `--max-run-duration=30m` to `--max-run-duration=60m`.
     - Add `serial-port-logging-enable=true` to `--metadata`.
   - Add a step `Wait for ARM Runner Registration`:
     - Poll `https://api.github.com/repos/${{ github.repository }}/actions/runners` every 5 seconds for up to 180 seconds (3 minutes) using `steps.app-token.outputs.token`.
     - Check if any runner has label matching `RUNNER_LABEL` and status `online` or `idle`.
     - If runner comes online, print success message and proceed.
     - If timeout expires, dump instance serial port output via `gcloud compute instances get-serial-port-output "${INSTANCE_NAME}" --project="${{ env.GCP_PROJECT }}" --zone="${{ env.GCP_ZONE }}"` and exit 1.
2. In `teardown-arm-runner`:
   - Update `if` condition to:
     `if: always() && needs.launch-arm-runner.outputs.instance-name != ''`
     so that even if `launch-arm-runner` fails during runner registration polling, the created VM is cleaned up immediately.

- [ ] **Step 4: Run validation script to verify it passes**

Run: `python3 tests/test_workflow_syntax.py`
Expected: PASS

- [ ] **Step 5: Commit changes**

```bash
git add .github/workflows/release.yml tests/test_workflow_syntax.py
git commit -m "ci(release): add serial logging, 60m duration, and runner readiness check"
```

---

### Task 3: End-to-End Validation & Verification

**Files:**
- Test: `tests/test_bootstrap_syntax.sh`, `tests/test_workflow_syntax.py`

- [ ] **Step 1: Run all test scripts**

Run:
```bash
./tests/test_bootstrap_syntax.sh
python3 tests/test_workflow_syntax.py
```
Expected: All PASS.

- [ ] **Step 2: Verify git status and clean working tree**

Run: `git status`
Expected: Working tree clean, commits ready for review.
