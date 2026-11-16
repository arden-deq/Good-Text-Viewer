// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "GoodTextViewer",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(name: "GoodTextViewerCore", targets: ["GoodTextViewerCore"]),
    .executable(name: "GoodTextViewer", targets: ["GoodTextViewer"]),
  ],
  targets: [
    .target(
      name: "GoodTextViewerCore",
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("CoreServices"),
        .linkedFramework("CoreText"),
      ]
    ),
    .executableTarget(
      name: "GoodTextViewer",
      dependencies: ["GoodTextViewerCore"],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("CoreText"),
        .linkedFramework("QuartzCore"),
        .linkedFramework("UniformTypeIdentifiers"),
      ]
    ),
    .testTarget(
      name: "GoodTextViewerCoreTests",
      dependencies: ["GoodTextViewerCore"]
    ),
    .testTarget(
      name: "GoodTextViewerTests",
      dependencies: ["GoodTextViewer", "GoodTextViewerCore"]
    ),
  ],
  swiftLanguageVersions: [.v5]
)
