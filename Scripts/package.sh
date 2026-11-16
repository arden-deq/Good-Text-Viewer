#!/bin/bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
readonly PRODUCT_NAME="GoodTextViewer"
readonly APP_NAME="Good Text Viewer"
readonly DIST_DIR="${PROJECT_ROOT}/dist"
readonly APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
readonly CONTENTS_DIR="${APP_BUNDLE}/Contents"
readonly MACOS_DIR="${CONTENTS_DIR}/MacOS"
readonly RESOURCES_DIR="${CONTENTS_DIR}/Resources"
readonly INFO_PLIST="${PROJECT_ROOT}/Packaging/Info.plist"
readonly APP_ICON="${PROJECT_ROOT}/Assets/AppIcon.icns"
readonly SWIFT="$(xcrun --find swift)"

if [[ ! -f "${PROJECT_ROOT}/Package.swift" ]]; then
  echo "error: Package.swift not found at ${PROJECT_ROOT}" >&2
  exit 1
fi

if [[ ! -f "${INFO_PLIST}" ]]; then
  echo "error: Info.plist not found at ${INFO_PLIST}" >&2
  exit 1
fi

"${PROJECT_ROOT}/Scripts/build-icon.sh"

if [[ ! -f "${APP_ICON}" ]]; then
  echo "error: generated app icon not found at ${APP_ICON}" >&2
  exit 1
fi

echo "Building ${PRODUCT_NAME} (release)..."
"${SWIFT}" build \
  --package-path "${PROJECT_ROOT}" \
  --configuration release \
  -Xswiftc -file-prefix-map \
  -Xswiftc "${PROJECT_ROOT}=." \
  --arch arm64 \
  --arch x86_64
readonly BIN_DIR="$("${SWIFT}" build \
  --package-path "${PROJECT_ROOT}" \
  --configuration release \
  --arch arm64 \
  --arch x86_64 \
  --show-bin-path)"
readonly BUILT_EXECUTABLE="${BIN_DIR}/${PRODUCT_NAME}"

if [[ ! -x "${BUILT_EXECUTABLE}" ]]; then
  echo "error: release executable not found at ${BUILT_EXECUTABLE}" >&2
  exit 1
fi

# Keep cleanup deliberately scoped to this one generated bundle.
if [[ "${APP_BUNDLE}" != "${PROJECT_ROOT}/dist/Good Text Viewer.app" ]]; then
  echo "error: refusing to clean unexpected app path: ${APP_BUNDLE}" >&2
  exit 1
fi

rm -rf -- "${APP_BUNDLE}"
mkdir -p -- "${MACOS_DIR}" "${RESOURCES_DIR}"
install -m 0755 "${BUILT_EXECUTABLE}" "${MACOS_DIR}/${PRODUCT_NAME}"
# Remove linker debug maps that contain absolute paths to build inputs.
xcrun strip -S "${MACOS_DIR}/${PRODUCT_NAME}"
install -m 0644 "${INFO_PLIST}" "${CONTENTS_DIR}/Info.plist"
install -m 0644 "${APP_ICON}" "${RESOURCES_DIR}/AppIcon.icns"

plutil -lint "${CONTENTS_DIR}/Info.plist" >/dev/null

if [[ -n "${GOOD_TEXT_VIEWER_SIGNING_IDENTITY:-}" ]]; then
  echo "Signing for distribution..."
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "${GOOD_TEXT_VIEWER_SIGNING_IDENTITY}" \
    "${APP_BUNDLE}"
else
  echo "Signing locally (ad-hoc)..."
  codesign --force --sign - --timestamp=none "${APP_BUNDLE}"
fi
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

echo "Created: ${APP_BUNDLE}"
