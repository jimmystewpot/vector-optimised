#!/usr/bin/env bash
set -uo pipefail

PROJECT_ID="${GCP_PROJECT:-oranged-experimentation}"
ZONE="${GCP_ZONE:-us-central1-a}"
INSTANCE_NAME="${1:-${GCP_INSTANCE_NAME:-}}"

if [[ -z "${INSTANCE_NAME}" ]]; then
  echo "Warning: No instance name provided to teardown script. Skipping."
  exit 0
fi

echo "=== Tearing Down Ephemeral GCP ARM Instance: ${INSTANCE_NAME} ==="
CLOUDSDK_METRICS_ENVIRONMENT=datacloud.antigravity gcloud compute instances delete "${INSTANCE_NAME}" \
  --project="${PROJECT_ID}" \
  --zone="${ZONE}" \
  --quiet || true

echo "Teardown command completed."
