#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_PROPERTIES="${ROOT_DIR}/android/key.properties"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Error: flutter is not installed or not in PATH."
  exit 1
fi

if [[ ! -f "${KEY_PROPERTIES}" ]]; then
  echo "Error: missing ${KEY_PROPERTIES}"
  echo "Copy or create android/key.properties with release signing credentials."
  exit 1
fi

STORE_FILE="$(sed -n 's/^storeFile=//p' "${KEY_PROPERTIES}" | head -n 1)"
if [[ -z "${STORE_FILE}" ]]; then
  echo "Error: storeFile is missing in ${KEY_PROPERTIES}"
  exit 1
fi

if [[ ! -f "${STORE_FILE}" ]]; then
  echo "Error: keystore file not found at ${STORE_FILE}"
  exit 1
fi

cd "${ROOT_DIR}"
flutter pub get
flutter build appbundle --release

echo "Done: ${ROOT_DIR}/build/app/outputs/bundle/release/app-release.aab"
