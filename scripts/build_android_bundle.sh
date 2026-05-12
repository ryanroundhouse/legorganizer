#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="${ROOT_DIR}/android"
KEY_PROPERTIES="${ROOT_DIR}/android/key.properties"
PUBSPEC_FILE="${ROOT_DIR}/pubspec.yaml"

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

if [[ "${STORE_FILE}" = /* ]]; then
  STORE_FILE_PATH="${STORE_FILE}"
else
  STORE_FILE_PATH="${ANDROID_DIR}/${STORE_FILE}"
fi

if [[ ! -f "${STORE_FILE_PATH}" ]]; then
  echo "Error: keystore file not found at ${STORE_FILE_PATH}"
  exit 1
fi

if [[ ! -f "${PUBSPEC_FILE}" ]]; then
  echo "Error: missing ${PUBSPEC_FILE}"
  exit 1
fi

CURRENT_VERSION_LINE="$(grep -m1 '^version:' "${PUBSPEC_FILE}" || true)"
if [[ -z "${CURRENT_VERSION_LINE}" ]]; then
  echo "Error: version field not found in ${PUBSPEC_FILE}"
  exit 1
fi

if [[ "${CURRENT_VERSION_LINE}" =~ ^version:[[:space:]]*([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)[[:space:]]*$ ]]; then
  MAJOR="${BASH_REMATCH[1]}"
  MINOR="${BASH_REMATCH[2]}"
  PATCH="${BASH_REMATCH[3]}"
  BUILD="${BASH_REMATCH[4]}"
else
  echo "Error: expected version format x.y.z+n in ${PUBSPEC_FILE}"
  echo "Found: ${CURRENT_VERSION_LINE}"
  exit 1
fi

NEW_PATCH=$((PATCH + 1))
NEW_BUILD=$((BUILD + 1))
OLD_VERSION="${MAJOR}.${MINOR}.${PATCH}+${BUILD}"
NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}+${NEW_BUILD}"

TMP_FILE="$(mktemp)"
awk -v new_version="${NEW_VERSION}" '
  BEGIN { updated = 0 }
  /^version:/ && updated == 0 {
    print "version: " new_version
    updated = 1
    next
  }
  { print }
  END {
    if (updated == 0) {
      exit 1
    }
  }
' "${PUBSPEC_FILE}" > "${TMP_FILE}"
mv "${TMP_FILE}" "${PUBSPEC_FILE}"
echo "Version bumped: ${OLD_VERSION} -> ${NEW_VERSION}"

cd "${ROOT_DIR}"
bash "${ROOT_DIR}/scripts/refresh_catalog.sh"
flutter pub get
flutter build appbundle --release

echo "Android App Bundle created:"
echo "${ROOT_DIR}/build/app/outputs/bundle/release/app-release.aab"
echo "Folder: ${ROOT_DIR}/build/app/outputs/bundle/release"
