#!/usr/bin/env bash
set -euo pipefail

TAG="${1:?Missing tag argument (e.g. v0.46.0)}"
VARIANT="${2:?Missing variant argument (e.g. aarch64-unknown-linux-gnu-lse)}"
BUILD_DIR="${3:-vector-src}"
OUT_DIR="artifacts"

PACKAGE_NAME="vector-${TAG}-${VARIANT}"
STAGE_DIR="target/staging/${PACKAGE_NAME}"

rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}/bin" "${STAGE_DIR}/config" "${STAGE_DIR}/systemd" "${OUT_DIR}"

echo "=== Packaging ${PACKAGE_NAME} ==="

if [[ ! -f "${BUILD_DIR}/target/release/vector" ]]; then
  echo "Error: Binary ${BUILD_DIR}/target/release/vector not found!" >&2
  exit 1
fi

echo "Staging binary..."
cp "${BUILD_DIR}/target/release/vector" "${STAGE_DIR}/bin/"
strip "${STAGE_DIR}/bin/vector" 2>/dev/null || true

echo "Staging configuration templates and service units..."
if [[ -f "${BUILD_DIR}/config/vector.yaml" ]]; then
  cp "${BUILD_DIR}/config/vector.yaml" "${STAGE_DIR}/config/"
fi
if [[ -f "${BUILD_DIR}/distribution/systemd/vector.service" ]]; then
  cp "${BUILD_DIR}/distribution/systemd/vector.service" "${STAGE_DIR}/systemd/"
fi
if [[ -f "${BUILD_DIR}/LICENSE" ]]; then
  cp "${BUILD_DIR}/LICENSE" "${STAGE_DIR}/"
fi
if [[ -f "README.md" ]]; then
  cp "README.md" "${STAGE_DIR}/"
fi

echo "Creating tarball ${OUT_DIR}/${PACKAGE_NAME}.tar.gz..."
tar -czf "${OUT_DIR}/${PACKAGE_NAME}.tar.gz" -C "target/staging" "${PACKAGE_NAME}"
echo "Successfully created: ${OUT_DIR}/${PACKAGE_NAME}.tar.gz"
ls -lh "${OUT_DIR}/${PACKAGE_NAME}.tar.gz"
