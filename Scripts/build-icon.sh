#!/bin/bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
readonly SOURCE_ART="${PROJECT_ROOT}/Assets/AppIcon-1024.png"
readonly SOURCE_ICON="${PROJECT_ROOT}/Assets/AppIcon-1024-final.png"
readonly OUTPUT_ICON="${PROJECT_ROOT}/Assets/AppIcon.icns"

if [[ ! -f "${SOURCE_ART}" ]]; then
  echo "error: icon artwork not found at ${SOURCE_ART}" >&2
  exit 1
fi

swift "${PROJECT_ROOT}/Scripts/make-rounded-icon.swift" "${SOURCE_ART}" "${SOURCE_ICON}"

readonly WIDTH="$(sips -g pixelWidth "${SOURCE_ICON}" | awk '/pixelWidth/ {print $2}')"
readonly HEIGHT="$(sips -g pixelHeight "${SOURCE_ICON}" | awk '/pixelHeight/ {print $2}')"
if [[ "${WIDTH}" != "1024" || "${HEIGHT}" != "1024" ]]; then
  echo "error: icon master must be 1024x1024 (got ${WIDTH}x${HEIGHT})" >&2
  exit 1
fi

readonly TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/good-text-viewer-icon.XXXXXX")"
trap 'rm -rf -- "${TEMP_DIR}"' EXIT
readonly ICONSET_DIR="${TEMP_DIR}/AppIcon.iconset"
mkdir -p -- "${ICONSET_DIR}"

make_icon() {
  local size="$1"
  local filename="$2"
  sips -z "${size}" "${size}" "${SOURCE_ICON}" --out "${ICONSET_DIR}/${filename}" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

mkdir -p -- "$(dirname -- "${OUTPUT_ICON}")"
iconutil --convert icns --output "${OUTPUT_ICON}" "${ICONSET_DIR}"
echo "Created: ${OUTPUT_ICON}"
