#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: make-publish-release.sh <github-owner>/<app-repository>" >&2
  exit 64
fi

if [[ -z "${GOOD_TEXT_VIEWER_SIGNING_IDENTITY:-}" ]]; then
  echo "error: set GOOD_TEXT_VIEWER_SIGNING_IDENTITY to a Developer ID Application identity" >&2
  exit 1
fi

if [[ -z "${GOOD_TEXT_VIEWER_NOTARY_PROFILE:-}" ]]; then
  echo "error: set GOOD_TEXT_VIEWER_NOTARY_PROFILE to a notarytool keychain profile" >&2
  exit 1
fi

readonly GITHUB_REPOSITORY="$1"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
readonly APP_BUNDLE="${PROJECT_ROOT}/dist/Good Text Viewer.app"
readonly NOTARY_ARCHIVE="${PROJECT_ROOT}/dist/Good-Text-Viewer-notarization.zip"

GOOD_TEXT_VIEWER_SIGNING_IDENTITY="${GOOD_TEXT_VIEWER_SIGNING_IDENTITY}" \
  "${PROJECT_ROOT}/Scripts/package.sh"

rm -f -- "${NOTARY_ARCHIVE}"
ditto -c -k --keepParent "${APP_BUNDLE}" "${NOTARY_ARCHIVE}"
xcrun notarytool submit "${NOTARY_ARCHIVE}" \
  --keychain-profile "${GOOD_TEXT_VIEWER_NOTARY_PROFILE}" \
  --wait
xcrun stapler staple "${APP_BUNDLE}"
xcrun stapler validate "${APP_BUNDLE}"
spctl --assess --type execute --verbose=4 "${APP_BUNDLE}"
rm -f -- "${NOTARY_ARCHIVE}"

"${PROJECT_ROOT}/Scripts/make-release.sh" --use-existing-app
"${PROJECT_ROOT}/Scripts/render-cask.sh" "${GITHUB_REPOSITORY}"
