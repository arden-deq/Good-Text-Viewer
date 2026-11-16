import CoreFoundation
import CoreServices
import Foundation

public enum TextDocumentEncoding: String, Codable, CaseIterable, Sendable {
  case utf8 = "UTF-8"
  case utf16LittleEndian = "UTF-16 LE"
  case utf16BigEndian = "UTF-16 BE"
  case eucKR = "EUC-KR / CP949"
}

public struct LoadedTextDocument: Sendable {
  public let url: URL
  public let text: String
  public let encoding: TextDocumentEncoding
  public let fileSize: Int64
  public let modificationDate: Date?

  public init(
    url: URL,
    text: String,
    encoding: TextDocumentEncoding,
    fileSize: Int64,
    modificationDate: Date?
  ) {
    self.url = url
    self.text = text
    self.encoding = encoding
    self.fileSize = fileSize
    self.modificationDate = modificationDate
  }

  public var title: String {
    url.lastPathComponent
  }

  public var persistenceIdentity: String {
    let timestamp = modificationDate?.timeIntervalSince1970 ?? 0
    return "\(url.standardizedFileURL.path)|\(fileSize)|\(timestamp)"
  }
}

public enum TextDocumentError: LocalizedError, Equatable {
  case txtFilesOnly
  case notARegularFile
  case unreadable
  case binaryFile
  case unsupportedEncoding

  public var errorDescription: String? {
    switch self {
    case .txtFilesOnly:
      return "TXT 파일만 열 수 있습니다."
    case .notARegularFile:
      return "일반 TXT 파일이 아닙니다."
    case .unreadable:
      return "파일을 읽을 수 없습니다. 권한과 파일 상태를 확인해 주세요."
    case .binaryFile:
      return "텍스트가 아닌 파일로 보입니다."
    case .unsupportedEncoding:
      return "지원하는 문자 인코딩으로 읽을 수 없습니다."
    }
  }
}

public enum TextDocumentLoader {
  public static func load(
    from inputURL: URL,
    repairsLegacyHardWraps: Bool = true,
    cancellation: PaginationCancellation? = nil
  ) throws -> LoadedTextDocument {
    try throwIfCancelled(cancellation)
    let url = inputURL.standardizedFileURL
    guard url.pathExtension.caseInsensitiveCompare("txt") == .orderedSame else {
      throw TextDocumentError.txtFilesOnly
    }

    let values: URLResourceValues
    do {
      values = try url.resourceValues(forKeys: [
        .isRegularFileKey,
        .fileSizeKey,
        .contentModificationDateKey,
      ])
    } catch {
      throw TextDocumentError.unreadable
    }
    try throwIfCancelled(cancellation)

    guard values.isRegularFile == true else {
      throw TextDocumentError.notARegularFile
    }

    let data: Data
    do {
      data = try Data(contentsOf: url, options: [.mappedIfSafe, .uncached])
    } catch {
      throw TextDocumentError.unreadable
    }
    try throwIfCancelled(cancellation)

    let decoded = try decode(
      data,
      repairsLegacyHardWraps: repairsLegacyHardWraps,
      cancellation: cancellation
    )
    try throwIfCancelled(cancellation)
    return LoadedTextDocument(
      url: url,
      text: decoded.text,
      encoding: decoded.encoding,
      fileSize: Int64(values.fileSize ?? data.count),
      modificationDate: values.contentModificationDate
    )
  }

  public static func decode(
    _ data: Data,
    repairsLegacyHardWraps: Bool = true,
    cancellation: PaginationCancellation? = nil
  ) throws -> (text: String, encoding: TextDocumentEncoding) {
    try throwIfCancelled(cancellation)
    if data.isEmpty {
      return ("", .utf8)
    }

    if data.starts(with: [0xEF, 0xBB, 0xBF]) {
      let payload = data.dropFirst(3)
      guard !looksBinary(payload) else {
        throw TextDocumentError.binaryFile
      }
      guard let text = String(data: payload, encoding: .utf8) else {
        throw TextDocumentError.unsupportedEncoding
      }
      return try prepared(
        removeLeadingBOM(text),
        encoding: .utf8,
        repairsLegacyHardWraps: repairsLegacyHardWraps,
        cancellation: cancellation
      )
    }

    if data.starts(with: [0xFF, 0xFE]) {
      guard let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) else {
        throw TextDocumentError.unsupportedEncoding
      }
      return try prepared(
        removeLeadingBOM(text),
        encoding: .utf16LittleEndian,
        repairsLegacyHardWraps: repairsLegacyHardWraps,
        cancellation: cancellation
      )
    }

    if data.starts(with: [0xFE, 0xFF]) {
      guard let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) else {
        throw TextDocumentError.unsupportedEncoding
      }
      return try prepared(
        removeLeadingBOM(text),
        encoding: .utf16BigEndian,
        repairsLegacyHardWraps: repairsLegacyHardWraps,
        cancellation: cancellation
      )
    }

    if let text = String(data: data, encoding: .utf8) {
      if !looksBinary(data) {
        return try prepared(
          removeLeadingBOM(text),
          encoding: .utf8,
          repairsLegacyHardWraps: repairsLegacyHardWraps,
          cancellation: cancellation
        )
      }
      if let utf16 = decodeBOMLessUTF16(data) {
        return try prepared(
          utf16.text,
          encoding: utf16.encoding,
          repairsLegacyHardWraps: repairsLegacyHardWraps,
          cancellation: cancellation
        )
      }
      throw TextDocumentError.binaryFile
    }

    if let utf16 = decodeBOMLessUTF16(data) {
      return try prepared(
        utf16.text,
        encoding: utf16.encoding,
        repairsLegacyHardWraps: repairsLegacyHardWraps,
        cancellation: cancellation
      )
    }

    guard !looksBinary(data) else {
      throw TextDocumentError.binaryFile
    }

    for encoding in koreanEncodings {
      try throwIfCancelled(cancellation)
      if let text = String(data: data, encoding: encoding) {
        return try prepared(
          removeLeadingBOM(text),
          encoding: .eucKR,
          repairsLegacyHardWraps: repairsLegacyHardWraps,
          cancellation: cancellation
        )
      }
    }

    throw TextDocumentError.unsupportedEncoding
  }

  private static var koreanEncodings: [String.Encoding] {
    let dosKorean = CFStringConvertEncodingToNSStringEncoding(
      CFStringEncoding(CFStringEncodings.dosKorean.rawValue)
    )
    let eucKorean = CFStringConvertEncodingToNSStringEncoding(
      CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
    )
    return [
      String.Encoding(rawValue: dosKorean),
      String.Encoding(rawValue: eucKorean),
    ]
  }

  private static func decodeBOMLessUTF16(_ data: Data) -> (
    text: String, encoding: TextDocumentEncoding
  )? {
    guard data.count >= 4, data.count.isMultiple(of: 2) else { return nil }

    let sample = Array(data.prefix(min(data.count, 8_192)))
    var evenNUL = 0
    var oddNUL = 0
    for (index, byte) in sample.enumerated() where byte == 0 {
      if index.isMultiple(of: 2) {
        evenNUL += 1
      } else {
        oddNUL += 1
      }
    }

    let pairs = max(1, sample.count / 2)
    let minimumSignal = max(2, pairs / 50)
    var littleEndianNewlines = 0
    var bigEndianNewlines = 0
    for index in stride(from: 0, to: sample.count - 1, by: 2) {
      if sample[index] == 0, sample[index + 1] == 0x0A || sample[index + 1] == 0x0D {
        bigEndianNewlines += 1
      }
      if sample[index + 1] == 0, sample[index] == 0x0A || sample[index] == 0x0D {
        littleEndianNewlines += 1
      }
    }

    let littleEndianText = String(data: data, encoding: .utf16LittleEndian)
    let bigEndianText = String(data: data, encoding: .utf16BigEndian)

    if littleEndianNewlines > bigEndianNewlines,
      let text = littleEndianText, isPlausibleText(text)
    {
      return (removeLeadingBOM(text), .utf16LittleEndian)
    }
    if bigEndianNewlines > littleEndianNewlines,
      let text = bigEndianText, isPlausibleText(text)
    {
      return (removeLeadingBOM(text), .utf16BigEndian)
    }
    if oddNUL - evenNUL >= minimumSignal,
      let text = littleEndianText, isPlausibleText(text)
    {
      return (removeLeadingBOM(text), .utf16LittleEndian)
    }
    if evenNUL - oddNUL >= minimumSignal,
      let text = bigEndianText, isPlausibleText(text)
    {
      return (removeLeadingBOM(text), .utf16BigEndian)
    }
    return nil
  }

  private static func isPlausibleText(_ text: String) -> Bool {
    var total = 0
    var suspicious = 0
    for scalar in text.unicodeScalars.prefix(4_096) {
      total += 1
      let value = scalar.value
      if value == 0
        || value < 0x09
        || (value > 0x0D && value < 0x20)
        || (value >= 0x7F && value <= 0x9F)
      {
        suspicious += 1
      }
    }
    return total > 0 && Double(suspicious) / Double(total) < 0.01
  }

  private static func looksBinary(_ data: Data) -> Bool {
    let sample = data.prefix(min(data.count, 16_384))
    guard !sample.isEmpty else { return false }

    var suspicious = 0
    for byte in sample {
      if byte == 0 {
        return true
      }
      if byte < 0x09 || (byte > 0x0D && byte < 0x20) {
        suspicious += 1
      }
    }
    return Double(suspicious) / Double(sample.count) > 0.01
  }

  private static func removeLeadingBOM(_ text: String) -> String {
    guard text.unicodeScalars.first?.value == 0xFEFF else { return text }
    return String(text.unicodeScalars.dropFirst())
  }

  private static func prepared(
    _ text: String,
    encoding: TextDocumentEncoding,
    repairsLegacyHardWraps: Bool,
    cancellation: PaginationCancellation?
  ) throws -> (text: String, encoding: TextDocumentEncoding) {
    // Fixed-width hard wrapping is a document trait, not an encoding trait. Some
    // old files have since been converted to UTF-8, while recent CP949 files may
    // contain intentional paragraph breaks. The detector inside `reflow` only
    // changes text after it finds a strong, repeated fixed-width pattern.
    try throwIfCancelled(cancellation)
    let preparedText =
      repairsLegacyHardWraps
      ? LegacyHardWrapReflow.reflow(text, cancellation: cancellation)
      : text
    try throwIfCancelled(cancellation)
    return (preparedText, encoding)
  }

  private static func throwIfCancelled(_ cancellation: PaginationCancellation?) throws {
    if cancellation?.isCancelled == true {
      throw CancellationError()
    }
  }
}

enum LegacyHardWrapReflow {
  private static let minimumMeasuredWidth = 40
  private static let clusterRadius = 2

  static func reflow(
    _ source: String,
    cancellation: PaginationCancellation? = nil,
    knownKoreanWord: (String) -> Bool = SystemKoreanDictionary.contains
  ) -> String {
    guard cancellation?.isCancelled != true else { return source }
    guard source.unicodeScalars.contains(where: { $0.value == 0x0A || $0.value == 0x0D }) else {
      return source
    }

    let normalized =
      source
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    guard cancellation?.isCancelled != true else { return source }
    let lines = normalized.components(separatedBy: "\n")
    guard lines.count > 1,
      let wrapWidth = detectedWrapWidth(in: lines, cancellation: cancellation)
    else {
      return source
    }

    let joinThreshold = max(minimumMeasuredWidth, wrapWidth - 3)
    var joinCandidateCount = 0
    var terminalJoinCandidateCount = 0
    var wrappedParagraphEndCount = 0
    for index in lines.indices.dropLast() {
      guard cancellation?.isCancelled != true else { return source }
      if shouldJoin(lines[index], to: lines[index + 1], threshold: joinThreshold) {
        joinCandidateCount += 1
        if endsInSentenceTerminator(lines[index]) {
          terminalJoinCandidateCount += 1
        }
        let nextLine = lines[index + 1]
        if displayWidth(of: nextLine) < joinThreshold,
          endsInSentenceTerminator(nextLine),
          startsNewParagraph(after: index + 1, in: lines)
        {
          wrappedParagraphEndCount += 1
        }
      }
    }
    guard joinCandidateCount >= max(4, lines.count / 20) else { return source }
    guard terminalJoinCandidateCount * 5 < joinCandidateCount else { return source }
    // A repeated column width alone is ambiguous: recent notes, verse, and generated
    // lists can intentionally contain many equally sized lines. Mechanical wrapping
    // also produces a second signal — full-width lines followed by shorter sentence
    // endings. Require several of those before changing any line break. Documents
    // without this evidence stay byte-for-byte equivalent after decoding and can
    // still be viewed with repair disabled from the View menu.
    guard wrappedParagraphEndCount >= max(4, joinCandidateCount / 10) else { return source }
    guard let evidence = BoundaryEvidence(lines: lines, cancellation: cancellation) else {
      return source
    }
    var parts: [String] = []
    parts.reserveCapacity(lines.count * 2)
    var stripLeadingWhitespace = false
    var didJoin = false

    for index in lines.indices {
      guard cancellation?.isCancelled != true else { return source }
      var renderedLine =
        stripLeadingWhitespace
        ? trimmingLeadingHorizontalWhitespace(lines[index])
        : lines[index]
      let shouldJoinNext =
        index < lines.count - 1
        && shouldJoin(
          lines[index],
          to: lines[index + 1],
          threshold: joinThreshold
        )

      if shouldJoinNext {
        didJoin = true
        renderedLine = trimmingTrailingHorizontalWhitespace(renderedLine)
      }
      parts.append(renderedLine)

      guard index < lines.count - 1 else { continue }
      if shouldJoinNext {
        let nextContent = trimmingLeadingHorizontalWhitespace(lines[index + 1])
        let hadTrailingWhitespace = lines[index].last.map(isHorizontalWhitespace) == true
        parts.append(
          boundarySeparator(
            after: renderedLine,
            before: nextContent,
            hadTrailingWhitespace: hadTrailingWhitespace,
            evidence: evidence,
            cancellation: cancellation,
            knownKoreanWord: knownKoreanWord
          )
        )
        stripLeadingWhitespace = true
      } else {
        parts.append("\n")
        stripLeadingWhitespace = false
      }
    }

    return didJoin ? parts.joined() : source
  }

  private static func startsNewParagraph(after lineIndex: Int, in lines: [String]) -> Bool {
    let followingIndex = lineIndex + 1
    guard followingIndex < lines.count else { return true }
    let followingLine = lines[followingIndex]
    return followingLine.trimmingCharacters(in: .whitespaces).isEmpty
      || leadingHorizontalWhitespaceWidth(in: followingLine) > 0
  }

  private static func detectedWrapWidth(
    in lines: [String],
    cancellation: PaginationCancellation?
  ) -> Int? {
    var widths: [Int] = []
    widths.reserveCapacity(lines.count)
    for line in lines {
      guard cancellation?.isCancelled != true else { return nil }
      guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
      let width = displayWidth(of: line)
      if width >= minimumMeasuredWidth {
        widths.append(width)
      }
    }
    guard widths.count >= 20 else { return nil }

    var histogram: [Int: Int] = [:]
    for width in widths {
      histogram[width, default: 0] += 1
    }

    let candidate = histogram.keys.max { left, right in
      let leftCount = clusteredCount(around: left, histogram: histogram)
      let rightCount = clusteredCount(around: right, histogram: histogram)
      if leftCount == rightCount { return left < right }
      return leftCount < rightCount
    }
    guard let candidate else { return nil }

    let clustered = clusteredCount(around: candidate, histogram: histogram)
    let requiredCluster = max(8, widths.count / 5)
    let sortedWidths = widths.sorted()
    let upperQuartile = sortedWidths[(sortedWidths.count * 3) / 4]
    guard clustered >= requiredCluster,
      candidate >= Int(Double(upperQuartile) * 0.85)
    else { return nil }
    return candidate
  }

  private static func clusteredCount(
    around width: Int,
    histogram: [Int: Int]
  ) -> Int {
    ((width - clusterRadius)...(width + clusterRadius)).reduce(0) {
      $0 + histogram[$1, default: 0]
    }
  }

  private static func shouldJoin(
    _ currentLine: String,
    to nextLine: String,
    threshold: Int
  ) -> Bool {
    let currentContent = trimmingTrailingHorizontalWhitespace(currentLine)
    let nextContent = trimmingLeadingHorizontalWhitespace(nextLine)
    guard !currentContent.isEmpty,
      !nextContent.isEmpty,
      displayWidth(of: currentLine) >= threshold,
      !isStructuredLine(currentLine),
      !isStructuredLine(nextLine)
    else { return false }

    let nextIndent = leadingHorizontalWhitespaceWidth(in: nextLine)
    let currentIndent = leadingHorizontalWhitespaceWidth(in: currentLine)
    // Legacy Korean prose commonly starts paragraphs with either one/two ASCII
    // spaces or a single full-width space. Larger indentation remains protected
    // as a formatting block.
    return nextIndent == 0 && currentIndent <= 2
  }

  private static func isStructuredLine(_ line: String) -> Bool {
    if line.contains("\t") || line.hasSuffix("  ") { return true }
    let content = line.trimmingCharacters(in: .whitespaces)
    if content.hasPrefix("|") || content.hasPrefix("+") || content.hasPrefix("┌")
      || content.hasPrefix("├") || content.hasPrefix("└")
    {
      return true
    }

    var wideWhitespaceRuns = 0
    var currentRun = 0
    for character in content {
      if character == " " || character == "\u{3000}" {
        currentRun += 1
      } else {
        if currentRun >= 2 { wideWhitespaceRuns += 1 }
        currentRun = 0
      }
    }
    if currentRun >= 2 { wideWhitespaceRuns += 1 }
    return wideWhitespaceRuns >= 2
  }

  private static func endsInSentenceTerminator(_ line: String) -> Bool {
    var content = line.trimmingCharacters(in: .whitespaces)
    let trailingClosers = Set<Character>("'\"’”)]}』」】》〉")
    while content.last.map(trailingClosers.contains) == true {
      content.removeLast()
    }
    guard let last = content.last else { return false }
    return ".!?。！？…".contains(last)
  }

  private static func boundarySeparator(
    after currentLine: String,
    before nextLine: String,
    hadTrailingWhitespace: Bool,
    evidence: BoundaryEvidence,
    cancellation: PaginationCancellation?,
    knownKoreanWord: (String) -> Bool
  ) -> String {
    guard cancellation?.isCancelled != true else { return "" }
    guard let trailing = currentLine.last,
      let leading = nextLine.first
    else { return "" }
    if hadTrailingWhitespace { return " " }
    if trailing.isWhitespace || leading.isWhitespace { return "" }
    if openingPunctuation.contains(trailing) || closingPunctuation.contains(leading) {
      return ""
    }

    let trailingToken = tokenAtEnd(of: currentLine)
    let leadingToken = tokenAtStart(of: nextLine)
    if shouldAttachToNonHangulBoundary(
      trailing: trailing,
      leadingToken: leadingToken
    ) {
      return ""
    }
    guard isHangul(trailing), isHangul(leading) else { return " " }
    if containsDigit(trailingToken), isCounterToken(leadingToken) {
      return " "
    }
    let pairKey = BoundaryEvidence.pairKey(trailingToken, leadingToken)
    if evidence.spacedPairs.contains(pairKey) {
      return " "
    }
    let combinedToken = trailingToken + leadingToken
    if evidence.tokens.contains(combinedToken) || evidence.wordStems.contains(combinedToken) {
      return ""
    }
    for suffix in stemSuffixes
    where leadingToken.count > suffix.count && leadingToken.hasSuffix(suffix) {
      let leadingStem = String(leadingToken.dropLast(suffix.count))
      if evidence.wordStems.contains(trailingToken + leadingStem) { return "" }
    }
    if shouldKeepAuxiliarySeparated(after: trailingToken, before: leadingToken) {
      return " "
    }
    if isBoundNounBoundary(after: trailingToken, before: leadingToken) {
      return " "
    }
    if leadingToken == "가", trailingToken.hasSuffix("겠는") { return "" }
    if completeModifierEndings.contains(where: trailingToken.hasSuffix) { return " " }
    if shouldKeepPredicateSeparated(after: trailingToken, before: leadingToken) {
      return " "
    }
    if continuationPrefixes.contains(where: leadingToken.hasPrefix) {
      return ""
    }
    if exactAttachedLeadingTokens.contains(leadingToken) {
      return ""
    }
    if leadingToken == "터", trailingToken.hasSuffix("부") { return "" }
    if leadingToken == "다", isConjugatedBeforeDa(trailingToken) { return "" }
    if dictionarySupportsJoin(
      trailingToken: trailingToken,
      leadingToken: leadingToken,
      cancellation: cancellation,
      knownKoreanWord: knownKoreanWord
    ) {
      return ""
    }
    return " "
  }

  private static func isCounterToken(_ token: String) -> Bool {
    koreanCounters.contains { counter in
      guard token.hasPrefix(counter) else { return false }
      let remainder = String(token.dropFirst(counter.count))
      return remainder.isEmpty || exactParticleTokens.contains(remainder)
    }
  }

  private static func shouldAttachToNonHangulBoundary(
    trailing: Character,
    leadingToken: String
  ) -> Bool {
    guard trailing.isNumber || trailing == "%" else { return false }
    return nonHangulAttachedTokens.contains(leadingToken)
  }

  private static func shouldKeepAuxiliarySeparated(
    after trailingToken: String,
    before leadingToken: String
  ) -> Bool {
    guard leadingToken.hasPrefix("하") || leadingToken.hasPrefix("했") else {
      return false
    }
    return completedPriorEndings.contains(where: trailingToken.hasSuffix)
  }

  private static func isBoundNounBoundary(
    after trailingToken: String,
    before leadingToken: String
  ) -> Bool {
    guard boundNounPrefixes.contains(where: leadingToken.hasPrefix) else { return false }
    return completeModifierEndings.contains(where: trailingToken.hasSuffix)
      || completeModifierTokens.contains(trailingToken)
  }

  private static func shouldKeepPredicateSeparated(
    after trailingToken: String,
    before leadingToken: String
  ) -> Bool {
    guard predicatePrefixes.contains(where: leadingToken.hasPrefix) else { return false }
    return exactParticleTokens.contains { particle in
      trailingToken.count > particle.count && trailingToken.hasSuffix(particle)
    }
  }

  private static func dictionarySupportsJoin(
    trailingToken: String,
    leadingToken: String,
    cancellation: PaginationCancellation?,
    knownKoreanWord: (String) -> Bool
  ) -> Bool {
    guard cancellation?.isCancelled != true else { return false }
    let combined = trailingToken + leadingToken
    if isKnownKoreanWord(combined, fallback: knownKoreanWord) { return true }

    for suffix in dictionarySuffixes
    where leadingToken.count > suffix.count && leadingToken.hasSuffix(suffix) {
      guard cancellation?.isCancelled != true else { return false }
      let leadingStem = String(leadingToken.dropLast(suffix.count))
      guard !leadingStem.isEmpty else { continue }
      if isKnownKoreanWord(trailingToken + leadingStem, fallback: knownKoreanWord) { return true }
    }

    if auxiliaryHaTokens.contains(leadingToken),
      isKnownKoreanWord(trailingToken + "하다", fallback: knownKoreanWord)
    {
      return true
    }
    if leadingToken.hasPrefix("내지"),
      isKnownKoreanWord(trailingToken + "내다", fallback: knownKoreanWord)
    {
      return true
    }
    if leadingToken == "진",
      isKnownKoreanWord(trailingToken + "지다", fallback: knownKoreanWord)
    {
      return true
    }
    if leadingToken.hasSuffix("진다") {
      let prefix = String(leadingToken.dropLast(2))
      if !prefix.isEmpty,
        isKnownKoreanWord(trailingToken + prefix + "지다", fallback: knownKoreanWord)
      {
        return true
      }
    }
    for transformation in dictionaryLemmaTransformations
    where leadingToken.hasSuffix(transformation.ending) {
      guard cancellation?.isCancelled != true else { return false }
      let prefix = String(leadingToken.dropLast(transformation.ending.count))
      let lemma = trailingToken + prefix + transformation.replacement
      if isKnownKoreanWord(lemma, fallback: knownKoreanWord) { return true }
    }

    for particle in exactParticleTokens
    where leadingToken.count > particle.count && leadingToken.hasSuffix(particle) {
      let stem = String(leadingToken.dropLast(particle.count))
      if nominalCompoundSuffixes.contains(stem), !endsInParticle(trailingToken) {
        return true
      }
    }
    if leadingToken == "들인", !endsInParticle(trailingToken) {
      return true
    }
    return false
  }

  private static func isKnownKoreanWord(
    _ word: String,
    fallback: (String) -> Bool
  ) -> Bool {
    localKnownKoreanWords.contains(word) || fallback(word)
  }

  private static func endsInParticle(_ token: String) -> Bool {
    exactParticleTokens.contains { particle in
      token.count > particle.count && token.hasSuffix(particle)
    }
  }

  private static func isConjugatedBeforeDa(_ token: String) -> Bool {
    daPrecedingEndings.contains(where: token.hasSuffix)
  }

  private static func displayWidth(of line: String) -> Int {
    line.unicodeScalars.reduce(into: 0) { width, scalar in
      if CharacterSet.nonBaseCharacters.contains(scalar) {
        return
      }
      if scalar.value == 0x09 {
        width += 4
      } else {
        width += scalar.value < 0x80 ? 1 : 2
      }
    }
  }

  private static func leadingHorizontalWhitespaceWidth(in line: String) -> Int {
    displayWidth(of: String(line.prefix(while: isHorizontalWhitespace)))
  }

  private static func trimmingLeadingHorizontalWhitespace(_ line: String) -> String {
    String(line.drop(while: isHorizontalWhitespace))
  }

  private static func trimmingTrailingHorizontalWhitespace(_ line: String) -> String {
    String(line.reversed().drop(while: isHorizontalWhitespace).reversed())
  }

  private static func isHorizontalWhitespace(_ character: Character) -> Bool {
    character == " " || character == "\t" || character == "\u{00A0}"
      || character == "\u{3000}"
  }

  private static func tokenAtEnd(of line: String) -> String {
    String(line.reversed().prefix(while: isTokenCharacter).reversed())
  }

  private static func tokenAtStart(of line: String) -> String {
    String(line.prefix(while: isTokenCharacter))
  }

  private static func isTokenCharacter(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy {
      CharacterSet.alphanumerics.contains($0)
    }
  }

  private static func isHangul(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { scalar in
      (0x1100...0x11FF).contains(scalar.value)
        || (0x3130...0x318F).contains(scalar.value)
        || (0xAC00...0xD7A3).contains(scalar.value)
    }
  }

  private static func containsDigit(_ value: String) -> Bool {
    value.unicodeScalars.contains(where: CharacterSet.decimalDigits.contains)
  }

  private static let openingPunctuation = Set<Character>("([{『「【《〈“‘\"")
  private static let closingPunctuation = Set<Character>(",.!?:;)]}』」】》〉”’\"")
  private static let koreanCounters: Set<String> = [
    "개", "권", "대", "마리", "명", "번", "분", "시", "원", "월", "일", "장", "초",
  ]
  private static let completeModifierEndings = [
    "같은", "그런", "는", "다른", "된", "란", "로운", "많은", "새로운", "없는", "은", "있는",
    "적은", "저런", "한", "할", "이런", "일",
  ]
  private static let completeModifierTokens: Set<String> = [
    "본", "온", "갈", "난", "낼", "될", "볼", "쓴", "올",
  ]
  private static let boundNounPrefixes = [
    "것", "건", "데", "때문", "바", "수",
  ]
  private static let completedPriorEndings = [
    "야", "아야", "어야", "여야", "고", "지", "게", "며", "면서", "도록", "려고",
  ]
  private static let predicatePrefixes = [
    "없", "있", "아니", "되",
  ]
  private static let continuationPrefixes = [
    "니없", "면서", "스럽", "적으로", "적인", "적으", "려", "했", "하겠", "하는", "하며", "하면", "하지",
  ]
  private static let exactParticleTokens: Set<String> = [
    "가", "과", "는", "도", "를", "만", "에", "에게", "와", "은", "을", "의", "이", "까지", "로",
    "으로", "에서", "에서는", "에서도", "에게는", "에게서", "로서", "로써", "부터", "보다",
  ]
  private static let stemSuffixes = [
    "에게서는", "에게서", "에게는", "에서는", "에서도", "으로", "에서", "로서", "로써", "부터", "까지",
    "에게", "만으로", "만이", "점들을", "들을", "들이", "들과", "보다", "가", "과", "는", "도", "를", "만",
    "에", "와", "은", "을", "의", "이", "로",
  ]
  private static let dictionarySuffixes =
    stemSuffixes + [
      "이었다면", "이었지만", "이었다", "였지만", "였기", "였던", "였다", "었다", "았다", "웠다", "궜다",
      "했겠지만", "되었다", "스러운", "이기에는", "이기에", "하는", "라서", "한다", "하게", "하고", "하며",
      "하면", "해서", "했다", "하지", "들인", "들을", "되어", "된", "한", "할", "히", "들", "계",
    ]
  private static let exactAttachedLeadingTokens: Set<String> = exactParticleTokens.union([
    "고", "니", "서", "지", "워", "아야", "아서", "어야", "았다", "었다", "이었다", "였다", "였기",
    "었던", "웠다", "궜다", "이나", "인데", "이니", "이었지만", "이었다면", "라서", "리째", "으며",
    "니까", "서는", "더라도", "어나면", "러났다", "리지", "리며", "지라도", "지고", "질지", "지만", "면",
    "게", "어", "히", "밖에는",
  ])
  private static let auxiliaryHaTokens: Set<String> = [
    "한", "할", "하고", "한다", "하게", "했다", "하며", "하면", "해",
  ]
  private static let nominalCompoundSuffixes: Set<String> = [
    "들", "어",
  ]
  private static let nonHangulAttachedTokens: Set<String> = [
    "가", "과", "는", "도", "라", "라는", "라고", "를", "만", "씩", "에", "와", "은", "을", "의", "이",
    "까지", "로", "으로", "에서", "부터", "보다",
  ]
  private static let dictionaryLemmaTransformations: [(ending: String, replacement: String)] = [
    ("나드는", "나들다"),
    ("러보면서", "러보다"),
    ("갑기만", "갑다"),
    ("다리면서", "다리다"),
    ("리면서", "리다"),
    ("리며", "리다"),
    ("금고", "금다"),
    ("이기에는", "이다"),
  ]
  private static let daPrecedingEndings = [
    "였", "이었", "했", "있었", "없었", "됐", "된", "이",
  ]
  private static let localKnownKoreanWords: Set<String> = [
    "갖다", "경미", "관도", "글자", "기다리다", "나가떨어지다", "단축", "돌파", "드나들다",
    "둔탁하다", "멍하다", "모니터", "머금다", "반응", "받아들이다", "보장하다", "복원",
    "사회문제", "산짐승", "상승", "생산", "소탕하다", "어색하다", "언제든지", "없어지다",
    "연마", "영광", "이치다", "작업", "정도", "지휘", "차갑다", "착실", "철두철미", "클래스",
    "꺼내다", "타격", "탈탈", "특권", "학살", "형성", "형태", "헤매다", "확신하다", "둘러보다",
  ]

  private struct BoundaryEvidence {
    let tokens: Set<String>
    let wordStems: Set<String>
    let spacedPairs: Set<String>

    init?(lines: [String], cancellation: PaginationCancellation?) {
      var foundTokens: Set<String> = []
      var foundPairs: Set<String> = []
      for line in lines {
        guard cancellation?.isCancelled != true else { return nil }
        for chunk in line.split(whereSeparator: { $0.isWhitespace }) {
          let chunkText = String(chunk)
          for token in chunkText.split(whereSeparator: { !isTokenCharacter($0) }) {
            foundTokens.insert(String(token))
          }
        }

        let whitespaceChunks = line.split(whereSeparator: { $0.isWhitespace })
        for pair in zip(whitespaceChunks, whitespaceChunks.dropFirst()) {
          let left = tokenAtEnd(of: String(pair.0))
          let right = tokenAtStart(of: String(pair.1))
          guard !left.isEmpty, !right.isEmpty else { continue }
          foundPairs.insert(Self.pairKey(left, right))
        }
      }
      tokens = foundTokens
      var foundStems = foundTokens
      for token in foundTokens {
        for suffix in stemSuffixes
        where token.count > suffix.count && token.hasSuffix(suffix) {
          foundStems.insert(String(token.dropLast(suffix.count)))
        }
      }
      wordStems = foundStems
      spacedPairs = foundPairs
    }

    static func pairKey(_ left: String, _ right: String) -> String {
      left + "\u{0}" + right
    }
  }
}

private enum SystemKoreanDictionary {
  private static let lock = NSLock()
  private static var cache: [String: Bool] = [:]
  private static let cacheLimit = 4_096

  static func contains(_ word: String) -> Bool {
    guard (2...32).contains(word.count), word.allSatisfy(isHangul) else { return false }

    lock.lock()
    if let cached = cache[word] {
      lock.unlock()
      return cached
    }
    lock.unlock()

    let found: Bool = autoreleasepool {
      let text = word as CFString
      let range = CFRange(location: 0, length: CFStringGetLength(text))
      guard let definition = DCSCopyTextDefinition(nil, text, range) else { return false }
      _ = definition.takeRetainedValue()
      return true
    }

    lock.lock()
    if cache.count < cacheLimit {
      cache[word] = found
    }
    lock.unlock()
    return found
  }

  private static func isHangul(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { scalar in
      (0x1100...0x11FF).contains(scalar.value)
        || (0x3130...0x318F).contains(scalar.value)
        || (0xAC00...0xD7A3).contains(scalar.value)
    }
  }
}
