import CoreFoundation
import Foundation
import XCTest

@testable import GoodTextViewerCore

final class TextDocumentLoaderTests: XCTestCase {
  func testDecodesUTF8WithBOM() throws {
    var data = Data([0xEF, 0xBB, 0xBF])
    data.append(Data("한글과 emoji 📖".utf8))

    let result = try TextDocumentLoader.decode(data)

    XCTAssertEqual(result.text, "한글과 emoji 📖")
    XCTAssertEqual(result.encoding, .utf8)
  }

  func testDecodesUTF16LittleEndianWithBOM() throws {
    var data = Data([0xFF, 0xFE])
    data.append(try XCTUnwrap("느린 밤".data(using: .utf16LittleEndian)))

    let result = try TextDocumentLoader.decode(data)

    XCTAssertEqual(result.text, "느린 밤")
    XCTAssertEqual(result.encoding, .utf16LittleEndian)
  }

  func testDetectsBOMLessUTF16BigEndian() throws {
    let source = String(repeating: "가나다라마바사\n", count: 20)
    let data = try XCTUnwrap(source.data(using: .utf16BigEndian))

    let result = try TextDocumentLoader.decode(data)

    XCTAssertEqual(result.text, source)
    XCTAssertEqual(result.encoding, .utf16BigEndian)
  }

  func testDecodesKoreanLegacyEncoding() throws {
    let source = "한글 텍스트입니다."
    let rawEncoding = CFStringConvertEncodingToNSStringEncoding(
      CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
    )
    let encoding = String.Encoding(rawValue: rawEncoding)
    let data = try XCTUnwrap(source.data(using: encoding))

    let result = try TextDocumentLoader.decode(data)

    XCTAssertEqual(result.text, source)
    XCTAssertEqual(result.encoding, .eucKR)
  }

  func testRejectsBinaryData() {
    let data = Data([0, 1, 2, 3, 4, 5, 0, 255, 0, 128])

    XCTAssertThrowsError(try TextDocumentLoader.decode(data)) { error in
      XCTAssertEqual(error as? TextDocumentError, .binaryFile)
    }
  }

  func testRejectsUTF8ContainingNUL() {
    let data = Data("text\0hidden".utf8)

    XCTAssertThrowsError(try TextDocumentLoader.decode(data)) { error in
      XCTAssertEqual(error as? TextDocumentError, .binaryFile)
    }
  }

  func testLoadsOnlyTXTAndCapturesMetadata() throws {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let txtURL = folder.appendingPathComponent("책.TXT")
    try Data("첫 문장".utf8).write(to: txtURL)
    let document = try TextDocumentLoader.load(from: txtURL)
    XCTAssertEqual(document.text, "첫 문장")
    XCTAssertEqual(document.fileSize, 10)
    XCTAssertEqual(document.title, "책.TXT")

    let markdownURL = folder.appendingPathComponent("책.md")
    try Data("text".utf8).write(to: markdownURL)
    XCTAssertThrowsError(try TextDocumentLoader.load(from: markdownURL)) { error in
      XCTAssertEqual(error as? TextDocumentError, .txtFilesOnly)
    }
  }

  func testReflowsDetectedLegacyHardWrapsWithoutSplittingKoreanWords() {
    let hardWrappedLines = [
      " 로열 로드의 인기는 날이 갈수록 높아지고 있었다. 지난 주만 해도 등록된 아이템들의 숫자가 16만여",
      "개 정도였는데, 오늘은 16만 5천개나 되었다.",
      " 그렇다고 해서 지난주 경매에 붙여진 아이템들이 팔리지 않은 것이냐 하면 그건 또 아니다. 아주 터무",
      "니없는 고가에 올려놓았거나 사람들이 별로 원하지 않는 아이템들을 제외하고는, 거의 전부가 팔렸다.",
      " 판매된 아이템들은 거래가 완전히 끝나고 하루가 지나면 자동 삭제가 되는데, 그러고 나서 계속 새로운",
      "아이템들이 등록된 것이었다.",
      " 대신에 잡템들은 최소 3천원의 시작가를 책정해 두었다. 3천원도 되지 않는다면 굳이 번거로움을 감수하",
      "면서까지 파는 의미가 없다.",
    ]
    let source = Array(repeating: hardWrappedLines, count: 8)
      .flatMap { $0 }
      .joined(separator: "\r\n")

    let result = LegacyHardWrapReflow.reflow(source)

    XCTAssertTrue(result.contains("16만여 개 정도"), result)
    XCTAssertTrue(result.contains("아주 터무니없는 고가"), result)
    XCTAssertTrue(result.contains("계속 새로운 아이템들이"), result)
    XCTAssertTrue(result.contains("감수하면서까지"), result)
    XCTAssertFalse(result.contains("터무\n니없는"))
  }

  func testLegacyReflowPreservesBlankLinesShortListsAndIndentationBlocks() {
    let filler = Array(
      repeating: " 긴 문장을 고정 폭으로 저장한 오래된 문서가 자연스럽게 이어지도록 충분한 길이로 반복합니다",
      count: 24
    )
    let source =
      ([
        "차례",
        "첫 번째 장",
        "두 번째 장",
        "",
        "      옵션 : 공격력 증가.",
        "      제한 : 레벨 100.",
        "",
      ] + filler).joined(separator: "\r\n")

    let result = LegacyHardWrapReflow.reflow(source)

    XCTAssertTrue(result.hasPrefix("차례\r\n첫 번째 장\r\n두 번째 장\r\n\r\n"), result)
    XCTAssertTrue(result.contains("      옵션 : 공격력 증가.\r\n      제한 : 레벨 100."), result)
  }

  func testOrdinaryShortLineDocumentKeepsOriginalLineEndings() {
    let source = "첫 줄\r\n둘째 줄\r\n\r\n새 문단"

    XCTAssertEqual(LegacyHardWrapReflow.reflow(source), source)
  }

  func testLegacyReflowKeepsAmbiguousKoreanWordBoundariesSeparated() {
    let boundaries = [
      ("그", "자본을"),
      ("접고", "새로"),
      ("말", "못 할"),
      ("때에는", "거래소"),
      ("길이", "같다면"),
    ]
    var lines = ["터무니없는 일도 있었다.", "악기를 다루는 법을 배웠다."]
    for _ in 0..<5 {
      for boundary in boundaries {
        lines.append(" " + String(repeating: "가", count: 45) + " " + boundary.0)
        lines.append(boundary.1)
      }
      lines.append(" " + String(repeating: "가", count: 45) + " 터무")
      lines.append("니없는 상황이었다.")
      lines.append(" " + String(repeating: "가", count: 46) + " 악")
      lines.append("기가 있었다.")
    }

    let result = LegacyHardWrapReflow.reflow(lines.joined(separator: "\r\n"))

    for boundary in boundaries {
      XCTAssertTrue(result.contains("\(boundary.0) \(boundary.1)"), result)
    }
    XCTAssertTrue(result.contains("터무니없는 상황이었다."), result)
    XCTAssertTrue(result.contains("악기가 있었다."), result)
  }

  func testLegacyReflowRestoresCorpusAndGrammarSupportedBoundaries() {
    let boundaries = [
      ("무시당하", "고"),
      ("내세", "워"),
      ("언제까", "지고"),
      ("달려가", "서"),
      ("보", "석류"),
      ("회", "색으로"),
      ("이들", "이었다면"),
    ]
    var lines = ["보석류와 회색 물품이 이미 기록되어 있었다."]
    for _ in 0..<5 {
      for boundary in boundaries {
        lines.append(" " + String(repeating: "가", count: 46) + " " + boundary.0)
        lines.append(boundary.1 + " 다음 문장이 이어진다.")
      }
    }

    let result = LegacyHardWrapReflow.reflow(
      lines.joined(separator: "\r\n"),
      knownKoreanWord: { ["보석류", "회색"].contains($0) }
    )

    for boundary in boundaries {
      XCTAssertTrue(result.contains(boundary.0 + boundary.1), result)
      XCTAssertFalse(result.contains(boundary.0 + " " + boundary.1), result)
    }
  }

  func testLegacyReflowUsesWordLookupForConjugatedSplitWords() {
    let boundaries = [
      ("꺼", "내지", "꺼내다"),
      ("없어", "진", "없어지다"),
    ]
    var lines: [String] = []
    for _ in 0..<10 {
      for boundary in boundaries {
        lines.append(" " + String(repeating: "가", count: 46) + " " + boundary.0)
        lines.append(boundary.1 + " 다음 문장이 이어진다.")
      }
    }
    let knownWords = Set(boundaries.map(\.2))

    let result = LegacyHardWrapReflow.reflow(
      lines.joined(separator: "\r\n"),
      knownKoreanWord: knownWords.contains
    )

    XCTAssertTrue(result.contains("꺼내지"), result)
    XCTAssertTrue(result.contains("없어진"), result)
    XCTAssertFalse(result.contains("꺼 내지"), result)
    XCTAssertFalse(result.contains("없어 진"), result)
  }

  func testLegacyReflowKeepsSeparatedAuxiliariesAndExplicitTrailingSpace() {
    let boundaries = [
      ("알아내야", "하는", "알아내야 하는"),
      ("두꺼워야", "했다", "두꺼워야 했다"),
      ("전군 사기 ", "상승", "전군 사기 상승"),
    ]
    var lines: [String] = []
    for _ in 0..<8 {
      for boundary in boundaries {
        lines.append(" " + String(repeating: "가", count: 46) + " " + boundary.0)
        lines.append(boundary.1 + " 뒤 문장이 이어진다.")
      }
    }

    let result = LegacyHardWrapReflow.reflow(
      lines.joined(separator: "\r\n"),
      knownKoreanWord: { _ in false }
    )

    for boundary in boundaries {
      XCTAssertTrue(result.contains(boundary.2), result)
    }
    XCTAssertFalse(result.contains("알아내야하는"), result)
    XCTAssertFalse(result.contains("두꺼워야했다"), result)
    XCTAssertFalse(result.contains("사기상승"), result)
  }

  func testUTF8DecodeReflowsDetectedFixedWidthTextIndependentlyOfEncoding() throws {
    let hardWrappedLines = [
      " 로열 로드의 인기는 날이 갈수록 높아지고 있었다. 지난 주만 해도 등록된 아이템들의 숫자가 16만여",
      "개 정도였는데, 오늘은 16만 5천개나 되었다.",
      " 그렇다고 해서 지난주 경매에 붙여진 아이템들이 팔리지 않은 것이냐 하면 그건 또 아니다. 아주 터무",
      "니없는 고가에 올려놓았거나 사람들이 별로 원하지 않는 아이템들을 제외하고는, 거의 전부가 팔렸다.",
      " 판매된 아이템들은 거래가 완전히 끝나고 하루가 지나면 자동 삭제가 되는데, 그러고 나서 계속 새로운",
      "아이템들이 등록된 것이었다.",
    ]
    let source = Array(repeating: hardWrappedLines, count: 8)
      .flatMap { $0 }
      .joined(separator: "\r\n")

    let result = try TextDocumentLoader.decode(Data(source.utf8))

    XCTAssertTrue(result.text.contains("아주 터무니없는 고가"), result.text)
    XCTAssertTrue(result.text.contains("16만여 개 정도"), result.text)
    XCTAssertEqual(result.encoding, .utf8)
  }

  func testCP949DecodeReflowsStrongLegacyFixedWidthPattern() throws {
    let hardWrappedLines = [
      " 오래된 CP949 문서가 고정된 폭에서 저장되어 문장 중간이 잘렸고 다음 줄에서 자연스럽게 이어져야 하",
      "는 상황을 재현합니다.",
    ]
    let source = Array(repeating: hardWrappedLines, count: 24)
      .flatMap { $0 }
      .joined(separator: "\r\n")
    let rawEncoding = CFStringConvertEncodingToNSStringEncoding(
      CFStringEncoding(CFStringEncodings.dosKorean.rawValue)
    )
    let encoding = String.Encoding(rawValue: rawEncoding)
    let data = try XCTUnwrap(source.data(using: encoding))

    let result = try TextDocumentLoader.decode(data)

    XCTAssertTrue(result.text.contains("자연스럽게 이어져야 하는 상황"), result.text)
    XCTAssertFalse(result.text.contains("이어져야 하\n는 상황"), result.text)
    XCTAssertEqual(result.encoding, .eucKR)
  }

  func testLegacyReflowAcceptsTwoColumnParagraphIndentation() {
    let hardWrappedLines = [
      "  오래된 문단이 고정된 폭에서 저장되어 문장 중간이 잘렸고 다음 줄에서 자연스럽게 이어져야 하",
      "는 상황을 재현합니다.",
      "\u{3000}오래된 문단이 고정된 폭에서 저장되어 문장 중간이 잘렸고 다음 줄에서 자연스럽게 이어져야 하",
      "는 상황을 함께 재현합니다.",
    ]
    let source = Array(repeating: hardWrappedLines, count: 12)
      .flatMap { $0 }
      .joined(separator: "\r\n")

    let result = LegacyHardWrapReflow.reflow(source, knownKoreanWord: { _ in false })

    XCTAssertTrue(result.contains("이어져야 하는 상황"), result)
    XCTAssertFalse(result.contains("이어져야 하\n는 상황"), result)
    XCTAssertTrue(result.contains("  오래된 문단이"), result)
    XCTAssertTrue(result.contains("\u{3000}오래된 문단이"), result)
  }

  func testModernUTF8TextWithoutFixedWidthPatternPreservesLineEndings() throws {
    let source = "짧은 첫 문단입니다.\r\n길이가 다른 둘째 줄입니다.\r\n\r\n최근 문서의 새 문단입니다."

    let result = try TextDocumentLoader.decode(Data(source.utf8))

    XCTAssertEqual(result.text, source)
    XCTAssertEqual(result.encoding, .utf8)
  }

  func testModernCP949TextWithoutFixedWidthPatternPreservesLineEndings() throws {
    let source = "최근 문서의 첫 줄입니다.\r\n길이가 다른 둘째 줄입니다.\r\n\r\n의도한 새 문단입니다."
    let rawEncoding = CFStringConvertEncodingToNSStringEncoding(
      CFStringEncoding(CFStringEncodings.dosKorean.rawValue)
    )
    let encoding = String.Encoding(rawValue: rawEncoding)
    let data = try XCTUnwrap(source.data(using: encoding))

    let result = try TextDocumentLoader.decode(data)

    XCTAssertEqual(result.text, source)
    XCTAssertEqual(result.encoding, .eucKR)
  }

  func testModernCP949FixedWidthLinesWithoutTerminatorsPreserveLineEndings() throws {
    let lines = (1...28).map { index in
      String(format: "%02d ", index) + String(repeating: "가", count: 47)
    }
    let source = lines.joined(separator: "\r\n")
    let rawEncoding = CFStringConvertEncodingToNSStringEncoding(
      CFStringEncoding(CFStringEncodings.dosKorean.rawValue)
    )
    let encoding = String.Encoding(rawValue: rawEncoding)
    let data = try XCTUnwrap(source.data(using: encoding))

    let result = try TextDocumentLoader.decode(data)

    XCTAssertEqual(result.text, source)
    XCTAssertEqual(result.encoding, .eucKR)
  }

  func testModernFixedWidthTableKeepsRowsAndCRLF() {
    let rows = (1...28).map { index in
      String(format: "%03d", index) + "\talpha             \tbeta              "
    }
    let source = rows.joined(separator: "\r\n")

    XCTAssertEqual(LegacyHardWrapReflow.reflow(source), source)
  }

  func testModernFixedWidthOneSentencePerLineKeepsIntentionalBreaks() {
    let line = "이 줄은 사용자가 의도하여 직접 구분한 현대 문서의 한 항목입니다."
    let source = Array(repeating: line, count: 24).joined(separator: "\r\n")

    XCTAssertEqual(
      LegacyHardWrapReflow.reflow(source, knownKoreanWord: { _ in false }),
      source
    )
  }

  func testModernFixedWidthLinesWithoutTerminatorsKeepIntentionalBreaks() {
    let lines = (1...28).map { index in
      String(format: "%02d ", index) + String(repeating: "가", count: 47)
    }
    let source = lines.joined(separator: "\r\n")

    XCTAssertEqual(
      LegacyHardWrapReflow.reflow(source, knownKoreanWord: { _ in false }),
      source
    )
  }

  func testModernFixedWidthItemsWithSparseShortSentencesKeepIntentionalBreaks() {
    var lines: [String] = []
    for index in 1...28 {
      lines.append(String(format: "%02d ", index) + String(repeating: "가", count: 47))
      if [4, 10, 16, 22].contains(index) {
        lines.append("짧게 끝나는 의도된 항목입니다.")
      }
    }
    let source = lines.joined(separator: "\r\n")

    XCTAssertEqual(
      LegacyHardWrapReflow.reflow(source, knownKoreanWord: { _ in false }),
      source
    )
  }

  func testLegacyHardWrapRepairCanBeDisabledForOriginalLineBreaks() throws {
    let hardWrappedLines = [
      " 오래된 문서의 긴 문장이 고정 폭으로 저장되어 다음 줄까지 자연스럽게 이어져야 하는 상황을 만듭니다",
      "이 줄은 앞 문장의 나머지이지만 원문 유지 설정에서는 그대로 남아야 합니다.",
    ]
    let source = Array(repeating: hardWrappedLines, count: 16)
      .flatMap { $0 }
      .joined(separator: "\r\n")

    let result = try TextDocumentLoader.decode(
      Data(source.utf8),
      repairsLegacyHardWraps: false
    )

    XCTAssertEqual(result.text, source)
  }

  func testLegacyReflowUsesDeterministicLocalWordsForSplitInflections() {
    let boundaries = [
      ("둔탁", "한", "둔탁한"),
      ("드", "나드는", "드나드는"),
      ("보장", "해", "보장해"),
      ("꺼", "내지", "꺼내지"),
      ("없어", "진", "없어진"),
      ("둘", "러보면서", "둘러보면서"),
      ("받아들", "이기에는", "받아들이기에는"),
      ("나가", "떨어진다", "나가떨어진다"),
    ]
    var lines: [String] = []
    for _ in 0..<4 {
      for boundary in boundaries {
        lines.append(" " + String(repeating: "가", count: 46) + " " + boundary.0)
        lines.append(boundary.1 + " 다음 문장이 이어진다.")
      }
    }

    let result = LegacyHardWrapReflow.reflow(
      lines.joined(separator: "\r\n"),
      knownKoreanWord: { _ in false }
    )

    for boundary in boundaries {
      XCTAssertTrue(result.contains(boundary.2), result)
      XCTAssertFalse(result.contains(boundary.0 + " " + boundary.1), result)
    }
  }

  func testCancelledDecodeStopsBeforeReflow() {
    let cancellation = PaginationCancellation()
    cancellation.cancel()

    XCTAssertThrowsError(
      try TextDocumentLoader.decode(
        Data(String(repeating: "긴 문장입니다.\r\n", count: 10_000).utf8),
        cancellation: cancellation
      )
    ) { error in
      XCTAssertTrue(error is CancellationError)
    }
  }
}
