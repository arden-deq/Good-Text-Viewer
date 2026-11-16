cask "dev-dot-good-text-viewer" do
  version "1.0.0"
  sha256 "dcb8693f3a298069b2e41f9a35b5caba07e428ac1ce1903f740107a38bf81775"

  url "https://github.com/namjungduck/Good-Text-Viewer/releases/download/v#{version}/Good-Text-Viewer-#{version}-macOS-universal.zip"
  name "Good Text Viewer"
  desc "Fast TXT reader with single- and two-page layouts"
  homepage "https://github.com/namjungduck/Good-Text-Viewer"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "Good Text Viewer.app"

  zap trash: "~/Library/Preferences/com.devdot.goodtextviewer.plist"
end
