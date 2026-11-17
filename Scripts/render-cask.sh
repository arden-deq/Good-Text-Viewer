#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "usage: render-cask.sh <github-owner>/<app-repository>" >&2
  exit 64
fi

readonly GITHUB_REPOSITORY="$1"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
readonly INFO_PLIST="${PROJECT_ROOT}/Packaging/Info.plist"
readonly VERSION="$(plutil -extract CFBundleShortVersionString raw "${INFO_PLIST}")"
readonly RELEASE_ARCHIVE="${PROJECT_ROOT}/dist/Good-Text-Viewer-${VERSION}-macOS-universal.zip"
readonly TEMPLATE="${PROJECT_ROOT}/Packaging/homebrew/Casks/dev-dot-good-text-viewer.rb.template"
readonly OUTPUT_DIR="${PROJECT_ROOT}/dist/qt/Casks"
readonly OUTPUT="${OUTPUT_DIR}/dev-dot-good-text-viewer.rb"

if [[ ! -f "${RELEASE_ARCHIVE}" ]]; then
  echo "error: run Scripts/make-release.sh first" >&2
  exit 1
fi

readonly CHECKSUM="$(shasum -a 256 "${RELEASE_ARCHIVE}" | awk '{print $1}')"
mkdir -p -- "${OUTPUT_DIR}"
sed \
  -e "s|__GITHUB_REPOSITORY__|${GITHUB_REPOSITORY}|g" \
  -e "s|__SHA256__|${CHECKSUM}|g" \
  -e "s|__VERSION__|${VERSION}|g" \
  "${TEMPLATE}" >"${OUTPUT}"

ruby -c "${OUTPUT}" >/dev/null
echo "Created: ${OUTPUT}"
