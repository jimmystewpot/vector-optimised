#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_REPO="vectordotdev/vector"
DOWNSTREAM_REPO="${GITHUB_REPOSITORY:-jimmystewpot/vector-optimised}"
FORCE_TAG="${1:-}"

if [[ -n "${FORCE_TAG}" ]]; then
  echo "Force building tag: ${FORCE_TAG}"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "should_build=true" >> "$GITHUB_OUTPUT"
    echo "target_tag=${FORCE_TAG}" >> "$GITHUB_OUTPUT"
  fi
  exit 0
fi

echo "Checking latest release from https://github.com/${UPSTREAM_REPO}..."
LATEST_UPSTREAM=$(curl -s "https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest" | jq -r .tag_name)

if [[ -z "${LATEST_UPSTREAM}" || "${LATEST_UPSTREAM}" == "null" ]]; then
  echo "Error: Failed to fetch latest release from ${UPSTREAM_REPO}" >&2
  exit 1
fi

echo "Latest upstream release: ${LATEST_UPSTREAM}"
echo "Checking if ${LATEST_UPSTREAM} has already been published in ${DOWNSTREAM_REPO}..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://api.github.com/repos/${DOWNSTREAM_REPO}/releases/tags/${LATEST_UPSTREAM}")

if [[ "${HTTP_STATUS}" == "200" ]]; then
  echo "Release ${LATEST_UPSTREAM} already built and published in ${DOWNSTREAM_REPO}. Skipping."
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "should_build=false" >> "$GITHUB_OUTPUT"
    echo "target_tag=${LATEST_UPSTREAM}" >> "$GITHUB_OUTPUT"
  fi
else
  echo "New upstream release detected: ${LATEST_UPSTREAM}"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "should_build=true" >> "$GITHUB_OUTPUT"
    echo "target_tag=${LATEST_UPSTREAM}" >> "$GITHUB_OUTPUT"
  fi
fi
