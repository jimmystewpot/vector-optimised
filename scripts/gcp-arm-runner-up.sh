#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${GCP_PROJECT:-oranged-experimentation}"
ZONE="${GCP_ZONE:-us-central1-a}"
RUN_IDENTIFIER="${GITHUB_RUN_ID:-$(date +%s)}"
INSTANCE_NAME="${GCP_INSTANCE_NAME:-gha-arm-${RUN_IDENTIFIER}}"
REPO="${GITHUB_REPOSITORY:-jimmystewpot/vector-optimised}"
MACHINE_TYPE="${GCP_MACHINE_TYPE:-t2a-standard-16}"
GITHUB_TOKEN="${GITHUB_TOKEN:?GITHUB_TOKEN environment variable is required}"

echo "=== Provisioning Ephemeral GCP ARM Runner ==="
echo "Repository:   ${REPO}"
echo "Project:      ${PROJECT_ID}"
echo "Zone:         ${ZONE}"
echo "Machine Type: ${MACHINE_TYPE}"
echo "Instance:     ${INSTANCE_NAME}"

echo "Requesting GitHub Actions runner registration token..."
REG_TOKEN_RESP=$(curl -sX POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/${REPO}/actions/runners/registration-token")

REG_TOKEN=$(echo "${REG_TOKEN_RESP}" | jq -r '.token // empty')

if [[ -z "${REG_TOKEN}" ]]; then
  echo "Error: Failed to obtain runner registration token from GitHub API:" >&2
  echo "${REG_TOKEN_RESP}" >&2
  exit 1
fi

echo "Successfully acquired registration token."

# Startup script to configure the runner and self-terminate upon job completion
STARTUP_SCRIPT="#!/bin/bash
set -euo pipefail

# Fallback watchdog: Self-destruct after 90 minutes in case of network disconnect
(sleep 5400 && ZONE_SELF=\$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/zone | awk -F/ '{print \$NF}') && CLOUDSDK_METRICS_ENVIRONMENT=datacloud.antigravity gcloud compute instances delete \$(hostname) --zone=\${ZONE_SELF} --quiet) &

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  build-essential clang cmake libssl-dev pkg-config libsasl2-dev \
  curl jq git ca-certificates protobuf-compiler libz-dev

# Create runner user
useradd -m -s /bin/bash runner
echo 'runner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner

# Install Rust toolchain for runner
su - runner -c 'curl --proto \"=https\" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable'

# Install GitHub Actions runner
su - runner -c '
mkdir -p actions-runner && cd actions-runner
RUNNER_VERSION=\"2.322.0\"
curl -o actions-runner-linux-arm64.tar.gz -L \"https://github.com/actions/runner/releases/download/v\${RUNNER_VERSION}/actions-runner-linux-arm64-\${RUNNER_VERSION}.tar.gz\"
tar xzf ./actions-runner-linux-arm64.tar.gz
./config.sh --url \"https://github.com/${REPO}\" --token \"${REG_TOKEN}\" --labels \"self-hosted,linux,arm64,gcp-arm64,ephemeral\" --name \"${INSTANCE_NAME}\" --unattended --ephemeral
./run.sh
'

# Ephemeral self-deletion immediately after the runner finishes its job
ZONE_SELF=\$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/zone | awk -F/ '{print \$NF}')
echo 'Runner job completed. Deleting instance...'
CLOUDSDK_METRICS_ENVIRONMENT=datacloud.antigravity gcloud compute instances delete \$(hostname) --zone=\${ZONE_SELF} --quiet || true
"

echo "Creating Compute Engine instance..."
CLOUDSDK_METRICS_ENVIRONMENT=datacloud.antigravity gcloud compute instances create "${INSTANCE_NAME}" \
  --project="${PROJECT_ID}" \
  --zone="${ZONE}" \
  --machine-type="${MACHINE_TYPE}" \
  --image-family="ubuntu-2404-lts-arm64" \
  --image-project="ubuntu-os-cloud" \
  --boot-disk-size="100GB" \
  --boot-disk-type="pd-ssd" \
  --scopes="cloud-platform" \
  --metadata=startup-script="${STARTUP_SCRIPT}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "instance_name=${INSTANCE_NAME}" >> "$GITHUB_OUTPUT"
  echo "zone=${ZONE}" >> "$GITHUB_OUTPUT"
fi

echo "Ephemeral instance ${INSTANCE_NAME} created and running."
