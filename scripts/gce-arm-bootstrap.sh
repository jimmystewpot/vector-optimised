#!/usr/bin/env bash
set -euo pipefail

# Watchdog: Hard poweroff after 35 minutes in case of hung jobs
(sleep 2100 && poweroff) &

export DEBIAN_FRONTEND=noninteractive
apt-get update -qy
apt-get install -qy docker.io libicu-dev jq curl ca-certificates
systemctl enable --now docker

if ! id -u runner >/dev/null 2>&1; then
  useradd -m -s /bin/bash runner
  usermod -aG docker runner
fi

META_URL="http://metadata.google.internal/computeMetadata/v1/instance/attributes"
REPO=$(curl -sf -H "Metadata-Flavor: Google" "${META_URL}/github-repo")
TOKEN=$(curl -sf -H "Metadata-Flavor: Google" "${META_URL}/runner-token")
LABELS=$(curl -sf -H "Metadata-Flavor: Google" "${META_URL}/runner-labels")
RUNNER_VERSION="2.322.0"

su - runner -c "
  mkdir -p actions-runner && cd actions-runner
  curl -s -o actions-runner.tar.gz -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-arm64-${RUNNER_VERSION}.tar.gz
  tar xzf actions-runner.tar.gz
  ./config.sh --url \"https://github.com/${REPO}\" \
              --token \"${TOKEN}\" \
              --name \"\$(hostname)\" \
              --labels \"${LABELS}\" \
              --unattended \
              --ephemeral
  ./run.sh
"

# Immediate post-job shutdown to halt compute billing
poweroff
