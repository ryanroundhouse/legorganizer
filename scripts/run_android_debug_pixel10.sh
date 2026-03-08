#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADB_BIN="${ADB_BIN:-adb}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"

TARGET_SERIAL="${1:-${ANDROID_SERIAL:-}}"

if ! command -v "${ADB_BIN}" >/dev/null 2>&1; then
  echo "Error: ${ADB_BIN} is not installed or not in PATH."
  exit 1
fi

if ! command -v "${FLUTTER_BIN}" >/dev/null 2>&1; then
  echo "Error: ${FLUTTER_BIN} is not installed or not in PATH."
  exit 1
fi

if [[ -z "${TARGET_SERIAL}" ]]; then
  PIXEL10_SERIALS=()
  while IFS= read -r serial; do
    [[ -n "${serial}" ]] && PIXEL10_SERIALS+=("${serial}")
  done < <(
    "${ADB_BIN}" devices -l | awk '
      NR > 1 && $2 == "device" {
        serial = $1
        line = tolower($0)
        gsub("_", " ", line)
        if (line ~ /pixel[[:space:]]*10/) {
          print serial
        }
      }
    '
  )

  if [[ "${#PIXEL10_SERIALS[@]}" -eq 0 ]]; then
    echo "Error: no connected Pixel 10 device found."
    echo
    echo "Connected Android devices:"
    "${ADB_BIN}" devices -l
    echo
    echo "Tip: pass a serial manually:"
    echo "  $0 <device-serial>"
    exit 1
  fi

  if [[ "${#PIXEL10_SERIALS[@]}" -gt 1 ]]; then
    echo "Error: multiple Pixel 10 devices found:"
    printf '  %s\n' "${PIXEL10_SERIALS[@]}"
    echo
    echo "Pass one explicitly:"
    echo "  $0 <device-serial>"
    exit 1
  fi

  TARGET_SERIAL="${PIXEL10_SERIALS[0]}"
fi

echo "Using Android device: ${TARGET_SERIAL}"
cd "${ROOT_DIR}"
"${FLUTTER_BIN}" run --debug -d "${TARGET_SERIAL}"
