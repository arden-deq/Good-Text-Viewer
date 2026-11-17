# Homebrew Tap package

`dev-dot-good-text-viewer` is the external-tap token for Good Text Viewer.

Public distribution requires a **Developer ID Application** identity and a configured `notarytool` keychain profile. Do not upload the default ad-hoc archive.

1. Run the complete signed publishing flow:

   ```sh
   GOOD_TEXT_VIEWER_SIGNING_IDENTITY="Developer ID Application: …" \
   GOOD_TEXT_VIEWER_NOTARY_PROFILE="notary-profile" \
   ./Scripts/make-publish-release.sh <owner>/<app-repository>
   ```

2. Upload the generated `Good-Text-Viewer-<version>-macOS-universal.zip` to the matching public GitHub release tagged `v<version>` without rebuilding it.
3. Copy the generated `dist/qt/Casks/dev-dot-good-text-viewer.rb` to `Casks/dev-dot-good-text-viewer.rb` in the public `<owner>/homebrew-tap` repository.
4. Validate from the tap repository with `brew style --cask Casks/dev-dot-good-text-viewer.rb` and `brew audit --new --cask dev-dot-good-text-viewer`.

For local verification only, `make release` creates an ad-hoc signed preview ZIP and `./Scripts/render-cask.sh <owner>/<app-repository>` renders a staging Cask. Neither is public-ready until the GitHub release exists and Gatekeeper accepts the app.
