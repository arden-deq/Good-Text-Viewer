import Foundation
import GoodTextViewerCore
import XCTest

@testable import GoodTextViewer

final class ReaderPreferencesTests: XCTestCase {
  private var suiteName = ""
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    suiteName = "ReaderPreferencesTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    super.tearDown()
  }

  func testReadingPositionsAreSeparatedByHardWrapRepairMode() {
    let preferences = ReaderPreferences(defaults: defaults)
    let document = makeDocument(text: String(repeating: "가", count: 200))

    preferences.save(anchor: 32, for: document, repairsLegacyHardWraps: true)
    preferences.save(anchor: 91, for: document, repairsLegacyHardWraps: false)

    XCTAssertEqual(preferences.anchor(for: document, repairsLegacyHardWraps: true), 32)
    XCTAssertEqual(preferences.anchor(for: document, repairsLegacyHardWraps: false), 91)
  }

  func testLegacyPositionBelongsOnlyToDefaultRepairMode() throws {
    let document = makeDocument(text: String(repeating: "가", count: 200))
    let timestamp = document.modificationDate?.timeIntervalSince1970 ?? 0
    let legacyEntry: [[String: Any]] = [
      [
        "path": document.url.standardizedFileURL.path,
        "fileSize": document.fileSize,
        "modificationTime": timestamp,
        "anchor": 47,
      ]
    ]
    defaults.set(
      try JSONSerialization.data(withJSONObject: legacyEntry),
      forKey: "readingPositions.v1"
    )
    let preferences = ReaderPreferences(defaults: defaults)

    XCTAssertEqual(preferences.anchor(for: document, repairsLegacyHardWraps: true), 47)
    XCTAssertEqual(preferences.anchor(for: document, repairsLegacyHardWraps: false), 0)
  }

  private func makeDocument(text: String) -> LoadedTextDocument {
    LoadedTextDocument(
      url: URL(fileURLWithPath: "/tmp/reader-position.txt"),
      text: text,
      encoding: .utf8,
      fileSize: 1234,
      modificationDate: Date(timeIntervalSince1970: 1_725_000_000)
    )
  }
}
