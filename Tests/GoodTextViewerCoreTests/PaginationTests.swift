import AppKit
import Foundation
import XCTest

@testable import GoodTextViewerCore

final class PaginationTests: XCTestCase {
  func testPaginationRangesAreContinuousAndReachEOF() {
    let text = String(repeating: "한글 본문과 emoji 👨‍👩‍👧‍👦가 함께 있는 문장입니다.\n\n", count: 120)
    let pages = paginate(text: text)

    XCTAssertGreaterThan(pages.count, 1)
    XCTAssertEqual(pages.first?.location, 0)
    for pair in zip(pages, pages.dropFirst()) {
      XCTAssertGreaterThan(pair.0.length, 0)
      XCTAssertEqual(pair.0.upperBound, pair.1.location)
    }
    XCTAssertEqual(pages.last?.upperBound, (text as NSString).length)
  }

  func testEmptyTextProducesOneEmptyPage() {
    let pages = paginate(text: "")

    XCTAssertEqual(pages, [PageRange(location: 0, length: 0)])
  }

  func testAnchorLookupFindsCorrectPageAndClampsPastEOF() {
    let pages = [
      PageRange(location: 0, length: 10),
      PageRange(location: 10, length: 20),
      PageRange(location: 30, length: 5),
    ]

    XCTAssertEqual(PaginationEngine.pageIndex(containing: 0, in: pages), 0)
    XCTAssertEqual(PaginationEngine.pageIndex(containing: 10, in: pages), 1)
    XCTAssertEqual(PaginationEngine.pageIndex(containing: 29, in: pages), 1)
    XCTAssertEqual(PaginationEngine.pageIndex(containing: 999, in: pages), 2)
  }

  func testProgressAnchorClampsAndRounds() {
    XCTAssertEqual(PaginationEngine.anchor(forProgress: -1, textLength: 101), 0)
    XCTAssertEqual(PaginationEngine.anchor(forProgress: 0.5, textLength: 101), 51)
    XCTAssertEqual(PaginationEngine.anchor(forProgress: 2, textLength: 101), 101)
    XCTAssertEqual(PaginationEngine.anchor(forProgress: 0.5, textLength: 0), 0)
  }

  func testLetterSpacingIsAppliedToLayout() throws {
    let layout = try captureLayout(
      text: "자간을 확인합니다.",
      configuration: TextLayoutConfiguration(
        pageWidth: 260,
        pageHeight: 180,
        fontSize: 18,
        letterSpacing: 1.2
      )
    )

    let spacing = try XCTUnwrap(layout.layoutAttribute(.kern, at: 0) as? CGFloat)
    XCTAssertEqual(spacing, 1.2, accuracy: 0.001)
  }

  func testIndentedParagraphUsesHangingIndentForWrappedLines() throws {
    let layout = try captureLayout(
      text: "\u{3000}\u{3000}들여쓴 항목 설명이 다음 줄까지 길게 이어지는 문장입니다.",
      configuration: TextLayoutConfiguration(
        pageWidth: 150,
        pageHeight: 120,
        fontSize: 18
      )
    )

    let style = try XCTUnwrap(
      layout.layoutAttribute(.paragraphStyle, at: 0) as? NSParagraphStyle
    )
    XCTAssertEqual(style.firstLineHeadIndent, 0, accuracy: 0.001)
    XCTAssertGreaterThan(style.headIndent, 20)
    XCTAssertTrue(style.lineBreakStrategy.contains(.hangulWordPriority))
  }

  func testFixedWidthPaddingBeforeClosingBracketIsCollapsed() throws {
    let text = "      옵션 : 여성 NPC에 대한 호감 30 상승.                                 』"
    let layout = try captureLayout(
      text: text,
      configuration: TextLayoutConfiguration(
        pageWidth: 420,
        pageHeight: 180,
        fontSize: 18
      )
    )
    let closingLocation = (text as NSString).range(of: "』").location
    let paddingFont = try XCTUnwrap(
      layout.layoutAttribute(.font, at: closingLocation - 1) as? NSFont
    )

    XCTAssertGreaterThan(paddingFont.pointSize, 1)
    XCTAssertLessThan(paddingFont.pointSize, 18)
  }

  func testHangulWordPriorityDoesNotBreakShortKoreanWordAcrossPages() {
    let token = "일시적으로"
    let text = "사자후를 아주 많이 들어 노이로제가 생겼다. \(token) 적을 압박한다."
    let narrowConfiguration = TextLayoutConfiguration(
      pageWidth: 122,
      pageHeight: 28,
      fontSize: 18,
      lineHeightMultiple: 1,
      paragraphSpacing: 0
    )
    let pages = paginate(text: text, configuration: narrowConfiguration)
    let tokenRange = (text as NSString).range(of: token)

    for boundary in pages.dropLast().map(\.upperBound) {
      XCTAssertFalse(
        boundary > tokenRange.location && boundary < NSMaxRange(tokenRange),
        "한글 단어 내부에서 페이지가 나뉘면 안 됩니다. boundary=\(boundary), token=\(tokenRange), pages=\(pages)"
      )
    }
  }

  func testAccessibleVisibleTextKeepsOriginalWhitespace() throws {
    let text = "사자후를 많이 들었다. 일시적으로 적을 압박하는 워리어의 기술이다."
    let configuration = TextLayoutConfiguration(
      pageWidth: 122,
      pageHeight: 56,
      fontSize: 18,
      lineHeightMultiple: 1,
      paragraphSpacing: 0
    )
    var capturedLayout: TextLayout?
    var pages: [PageRange] = []
    PaginationEngine.paginate(
      text: text,
      configuration: configuration,
      cancellation: PaginationCancellation(),
      batchSize: 2
    ) { layout, batch, _ in
      capturedLayout = layout
      pages.append(contentsOf: batch)
    }

    let visibleText = try XCTUnwrap(capturedLayout).visibleText(for: pages)
    XCTAssertFalse(visibleText.contains("\u{2028}"))
    XCTAssertTrue(visibleText.contains("일시적으로"))
  }

  func testCancellationStopsBeforePublishing() {
    let cancellation = PaginationCancellation()
    cancellation.cancel()
    var callbackCount = 0

    PaginationEngine.paginate(
      text: String(repeating: "문장 ", count: 1_000),
      configuration: configuration,
      cancellation: cancellation
    ) { _, _, _ in
      callbackCount += 1
    }

    XCTAssertEqual(callbackCount, 0)
  }

  func testLargeTextPublishesFirstPageWithoutFullPagination() {
    let paragraph = "빠르게 열리는 큰 문서를 위한 한글 문장입니다. Core Text 페이지를 확인합니다.\n\n"
    let text = String(repeating: paragraph, count: 100_000)
    let cancellation = PaginationCancellation()
    var publishedPage: PageRange?
    let start = CFAbsoluteTimeGetCurrent()

    PaginationEngine.paginate(
      text: text,
      configuration: configuration,
      cancellation: cancellation
    ) { _, pages, _ in
      publishedPage = pages.first
      cancellation.cancel()
    }

    let elapsed = CFAbsoluteTimeGetCurrent() - start
    XCTAssertNotNil(publishedPage)
    XCTAssertLessThan(elapsed, 2, "첫 페이지 생성이 전체 페이지 인덱스를 기다리면 안 됩니다.")
  }

  private var configuration: TextLayoutConfiguration {
    TextLayoutConfiguration(
      pageWidth: 260,
      pageHeight: 180,
      fontSize: 18
    )
  }

  private func paginate(text: String) -> [PageRange] {
    paginate(text: text, configuration: configuration)
  }

  private func paginate(
    text: String,
    configuration: TextLayoutConfiguration
  ) -> [PageRange] {
    var result: [PageRange] = []
    PaginationEngine.paginate(
      text: text,
      configuration: configuration,
      cancellation: PaginationCancellation(),
      batchSize: 3
    ) { _, pages, _ in
      result.append(contentsOf: pages)
    }
    return result
  }

  private func captureLayout(
    text: String,
    configuration: TextLayoutConfiguration
  ) throws -> TextLayout {
    var captured: TextLayout?
    let cancellation = PaginationCancellation()
    PaginationEngine.paginate(
      text: text,
      configuration: configuration,
      cancellation: cancellation
    ) { layout, _, _ in
      captured = layout
      cancellation.cancel()
    }
    return try XCTUnwrap(captured)
  }
}
