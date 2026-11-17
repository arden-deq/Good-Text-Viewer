cask "dev-dot-good-text-viewer" do
  version "1.2.1"
  sha256 "b268520e9a28b3bc37dd570a8e773a1453ccd1b4c28d01d3e94cbb3eba57c896"

  url "https://github.com/arden-deq/Good-Text-Viewer/releases/download/v#{version}/Good-Text-Viewer-#{version}-macOS-universal.zip"
  name "Good Text Viewer"
  desc "Fast TXT reader with single- and two-page layouts"
  homepage "https://github.com/arden-deq/Good-Text-Viewer"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "Good Text Viewer.app"

  zap trash: "~/Library/Preferences/com.devdot.goodtextviewer.plist"
end
