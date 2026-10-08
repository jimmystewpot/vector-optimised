#!/usr/bin/env python3
import sys

with open(".github/workflows/release.yml", "r") as f:
    content = f.read()

checks = [
    ("serial-port-logging-enable=true", "Missing serial port logging in GCE metadata"),
    ("max-run-duration=60m", "Expected max-run-duration=60m for long compilation"),
    ("actions/runners?per_page=100", "Missing per_page=100 in runner readiness polling URL"),
]

failed = False
for needle, err_msg in checks:
    if needle not in content:
        print(f"FAIL: {err_msg}", file=sys.stderr)
        failed = True

if failed:
    sys.exit(1)

print("PASS: release.yml validation checks passed.")
