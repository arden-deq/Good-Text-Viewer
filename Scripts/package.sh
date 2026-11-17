#!/bin/bash
set -euo pipefail

readonly ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BUILD="${ROOT}/.build/qt-universal"
readonly DIST="${ROOT}/dist/qt"
readonly APP="${DIST}/Good Text Viewer.app"
readonly CMAKE_BIN="${CMAKE_BIN:-cmake}"

mkdir -p -- "${DIST}"
stage="$(mktemp -d "${DIST}/package.XXXXXXXX")"
trap 'rm -rf -- "${stage}"' EXIT

"${CMAKE_BIN}" -S "${ROOT}" -B "${BUILD}" -DCMAKE_BUILD_TYPE=Release \
  '-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64' -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 -DBUILD_TESTING=OFF
"${CMAKE_BIN}" --build "${BUILD}" --config Release --parallel
"${CMAKE_BIN}" --install "${BUILD}" --config Release --prefix "${stage}"

readonly BUNDLE="${stage}/GoodTextViewer.app"
readonly BINARY="${BUNDLE}/Contents/MacOS/GoodTextViewer"
xcrun lipo "${BINARY}" -verify_arch arm64 x86_64
plutil -lint "${BUNDLE}/Contents/Info.plist" >/dev/null

if [[ -n "${GOOD_TEXT_VIEWER_SIGNING_IDENTITY:-}" ]]; then
  signing=(--sign "${GOOD_TEXT_VIEWER_SIGNING_IDENTITY}" --options runtime --timestamp)
else
  signing=(--sign - --timestamp=none)
fi
for framework in "${BUNDLE}/Contents/Frameworks/"*.framework; do
  xcrun lipo "${framework}/Versions/Current/$(basename "${framework}" .framework)" -verify_arch arm64 x86_64
  codesign --force "${signing[@]}" "${framework}/Versions/Current"
done
while IFS= read -r -d '' lib; do
  codesign --force "${signing[@]}" "${lib}"
done < <(find "${BUNDLE}/Contents/PlugIns" -type f -name '*.dylib' -print0)
codesign --force "${signing[@]}" "${BUNDLE}"
codesign --verify --deep --strict "${BUNDLE}"

if [[ -e "${APP}" ]]; then
  mv -- "${APP}" "${stage}/previous.app"
fi
if ! mv -- "${BUNDLE}" "${APP}"; then
  if [[ -e "${stage}/previous.app" ]]; then mv -- "${stage}/previous.app" "${APP}"; fi
  exit 1
fi
echo "Created: ${APP}"
