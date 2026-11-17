#!/bin/bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
app="${1:-$project_root/dist/qt/Good Text Viewer.app}"

: "${GOOD_TEXT_VIEWER_SIGNING_IDENTITY:?Set the Developer ID Application identity}"
: "${GOOD_TEXT_VIEWER_NOTARY_PROFILE:?Set the notarytool keychain profile}"

version="$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
codesign --verify --deep --strict "$app"
xcrun stapler validate "$app"

stage="$(mktemp -d "$project_root/dist/.dmg.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
mkdir "$stage/volume"
ditto "$app" "$stage/volume/Good Text Viewer.app"
ln -s /Applications "$stage/volume/Applications"

filename="Good-Text-Viewer-$version-macOS-universal.dmg"
dmg="$stage/$filename"
hdiutil create -volname "Good Text Viewer" -srcfolder "$stage/volume" -format UDZO -fs HFS+ "$dmg"
codesign --sign "$GOOD_TEXT_VIEWER_SIGNING_IDENTITY" --timestamp --identifier com.devdot.goodtextviewer.dmg "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$GOOD_TEXT_VIEWER_NOTARY_PROFILE" --wait --output-format json >"$stage/notary.json"
if [[ "$(plutil -extract status raw -o - "$stage/notary.json")" != Accepted ]]; then
    cat "$stage/notary.json" >&2
    exit 1
fi
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
codesign --verify --strict "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg"
(cd "$stage" && shasum -a 256 "$filename" > "$filename.sha256")
mv "$dmg" "$dmg.sha256" "$project_root/dist/"
