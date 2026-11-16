import Foundation
import GoodTextViewerCore

enum ReaderPageMode: Int, Codable {
  case single = 1
  case spread = 2

  var pageAdvance: Int { rawValue }
}

private struct StoredReadingPosition: Codable {
  let path: String
  let fileSize: Int64
  let modificationTime: TimeInterval
  let anchor: Int
  let repairsLegacyHardWraps: Bool?

  var repairMode: Bool {
    // Positions written before the repair toggle existed used the default (enabled) coordinate space.
    repairsLegacyHardWraps ?? true
  }
}

final class ReaderPreferences {
  static let shared = ReaderPreferences()

  private let defaults: UserDefaults
  private let positionsKey = "readingPositions.v1"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var fontSize: CGFloat {
    get {
      let stored = defaults.double(forKey: "fontSize")
      return stored == 0 ? 18 : CGFloat(stored).clamped(to: 12...36)
    }
    set { defaults.set(Double(newValue.clamped(to: 12...36)), forKey: "fontSize") }
  }

  var letterSpacing: CGFloat {
    get { CGFloat(defaults.double(forKey: "letterSpacing")).clamped(to: -0.5...2) }
    set { defaults.set(Double(newValue.clamped(to: -0.5...2)), forKey: "letterSpacing") }
  }

  var pageMode: ReaderPageMode {
    get { ReaderPageMode(rawValue: defaults.integer(forKey: "pageMode")) ?? .single }
    set { defaults.set(newValue.rawValue, forKey: "pageMode") }
  }

  var repairsLegacyHardWraps: Bool {
    get { (defaults.object(forKey: "repairsLegacyHardWraps") as? Bool) ?? true }
    set { defaults.set(newValue, forKey: "repairsLegacyHardWraps") }
  }

  var lastDocumentPath: String? {
    get { defaults.string(forKey: "lastDocumentPath") }
    set { defaults.set(newValue, forKey: "lastDocumentPath") }
  }

  func anchor(for document: LoadedTextDocument, repairsLegacyHardWraps: Bool) -> Int {
    guard
      let match = positions.first(where: {
        $0.path == document.url.standardizedFileURL.path
          && $0.fileSize == document.fileSize
          && abs($0.modificationTime - modificationTime(for: document)) < 0.001
          && $0.repairMode == repairsLegacyHardWraps
      })
    else {
      return 0
    }
    return max(0, min(match.anchor, (document.text as NSString).length))
  }

  func save(anchor: Int, for document: LoadedTextDocument, repairsLegacyHardWraps: Bool) {
    let path = document.url.standardizedFileURL.path
    var updated = positions.filter {
      $0.path != path || $0.repairMode != repairsLegacyHardWraps
    }
    updated.append(
      StoredReadingPosition(
        path: path,
        fileSize: document.fileSize,
        modificationTime: modificationTime(for: document),
        anchor: max(0, anchor),
        repairsLegacyHardWraps: repairsLegacyHardWraps
      )
    )
    if updated.count > 50 {
      updated.removeFirst(updated.count - 50)
    }
    positions = updated
    lastDocumentPath = path
  }

  private var positions: [StoredReadingPosition] {
    get {
      guard let data = defaults.data(forKey: positionsKey),
        let decoded = try? JSONDecoder().decode([StoredReadingPosition].self, from: data)
      else {
        return []
      }
      return decoded
    }
    set {
      guard let data = try? JSONEncoder().encode(newValue) else { return }
      defaults.set(data, forKey: positionsKey)
    }
  }

  private func modificationTime(for document: LoadedTextDocument) -> TimeInterval {
    document.modificationDate?.timeIntervalSince1970 ?? 0
  }
}

extension Comparable {
  fileprivate func clamped(to limits: ClosedRange<Self>) -> Self {
    min(max(self, limits.lowerBound), limits.upperBound)
  }
}
