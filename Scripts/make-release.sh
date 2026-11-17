#!/bin/bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
readonly INFO_PLIST="${PROJECT_ROOT}/Packaging/Info.plist"
readonly VERSION="$(plutil -extract CFBundleShortVersionString raw "${INFO_PLIST}")"
readonly APP_BUNDLE="${PROJECT_ROOT}/dist/qt/Good Text Viewer.app"
readonly RELEASE_NAME="Good-Text-Viewer-${VERSION}-macOS-universal"
readonly RELEASE_ARCHIVE="${PROJECT_ROOT}/dist/${RELEASE_NAME}.zip"
readonly CHECKSUM_FILE="${RELEASE_ARCHIVE}.sha256"

USE_EXISTING_APP=false
if [[ "${1:-}" == "--use-existing-app" ]]; then
  USE_EXISTING_APP=true
elif [[ $# -gt 0 ]]; then
  echo "usage: make-release.sh [--use-existing-app]" >&2
  exit 64
fi

if [[ "${USE_EXISTING_APP}" == false ]]; then
  bash "${PROJECT_ROOT}/Scripts/package.sh"
fi

if [[ ! -d "${APP_BUNDLE}" ]]; then
  echo "error: app bundle not found at ${APP_BUNDLE}" >&2
  exit 1
fi
if [[ "$(plutil -extract CFBundleShortVersionString raw "${APP_BUNDLE}/Contents/Info.plist")" != "${VERSION}" ]]; then
  echo "error: package version does not match ${VERSION}" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

if [[ "${RELEASE_ARCHIVE}" != "${PROJECT_ROOT}/dist/${RELEASE_NAME}.zip" ]]; then
  echo "error: refusing to replace unexpected release path: ${RELEASE_ARCHIVE}" >&2
  exit 1
fi

rm -f -- "${RELEASE_ARCHIVE}" "${CHECKSUM_FILE}"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${RELEASE_ARCHIVE}"

readonly CHECKSUM="$(shasum -a 256 "${RELEASE_ARCHIVE}" | awk '{print $1}')"
printf '%s  %s\n' "${CHECKSUM}" "$(basename -- "${RELEASE_ARCHIVE}")" >"${CHECKSUM_FILE}"

echo "Created: ${RELEASE_ARCHIVE}"
echo "SHA-256: ${CHECKSUM}"
