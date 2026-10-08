#!/usr/bin/env bash
set -euo pipefail

# Watchdog: Hard poweroff after 60 minutes in case of hung jobs
(sleep 3600 && poweroff) &

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
RUNNER_VERSION="2.338.0"

RUNNER_DIR="/home/runner/actions-runner"
mkdir -p "${RUNNER_DIR}"
cd "${RUNNER_DIR}"

# Download and unpack runner as root to install system dependencies
echo "Downloading GitHub Actions Runner v${RUNNER_VERSION}..."
curl -s -o actions-runner.tar.gz -L "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-arm64-${RUNNER_VERSION}.tar.gz"
tar xzf actions-runner.tar.gz

echo "Installing runner OS dependencies..."
./bin/installdependencies.sh

# Ensure user runner owns the runner directory
chown -R runner:runner "${RUNNER_DIR}"

echo "Configuring and starting runner as user 'runner'..."
if su - runner -c "
  set -euo pipefail
  cd '${RUNNER_DIR}'
  ./config.sh --url \"https://github.com/${REPO}\" \
              --token \"${TOKEN}\" \
              --name \"\$(hostname)\" \
              --labels \"${LABELS}\" \
              --unattended \
              --ephemeral
  ./run.sh
"; then
  echo "Runner finished job successfully. Halting instance to end billing."
  poweroff
else
  echo "ERROR: Runner setup or job execution failed! Preserving VM for watchdog / diagnosis." >&2
  exit 1
fi
