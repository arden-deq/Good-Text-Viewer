import AppKit
import CoreText
import Foundation

public struct PageRange: Equatable, Sendable {
  public let location: Int
  public let length: Int

  public init(location: Int, length: Int) {
    self.location = location
    self.length = length
  }

  public var upperBound: Int {
    location + length
  }

  public var nsRange: NSRange {
    NSRange(location: location, length: length)
  }
}

public struct TextLayoutConfiguration: Equatable, Sendable {
  public let pageWidth: CGFloat
  public let pageHeight: CGFloat
  public let fontSize: CGFloat
  public let lineHeightMultiple: CGFloat
  public let paragraphSpacing: CGFloat
  public let letterSpacing: CGFloat
  public let fontName: String

  public init(
    pageWidth: CGFloat,
    pageHeight: CGFloat,
    fontSize: CGFloat,
    lineHeightMultiple: CGFloat = 1.72,
    paragraphSpacing: CGFloat? = nil,
    letterSpacing: CGFloat = 0,
    fontName: String = "AppleMyungjo"
  ) {
    self.pageWidth = pageWidth.rounded(.down)
    self.pageHeight = pageHeight.rounded(.down)
    self.fontSize = fontSize
    self.lineHeightMultiple = lineHeightMultiple
    self.paragraphSpacing = paragraphSpacing ?? fontSize * 0.72
    self.letterSpacing = letterSpacing
    self.fontName = fontName
  }
}

public final class PaginationCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false

  public init() {}

  public func cancel() {
    lock.lock()
    value = true
    lock.unlock()
  }

  public var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

public final class TextLayout: @unchecked Sendable {
  public let configuration: TextLayoutConfiguration
  public let textLength: Int
  public let string: String

  private let attributedText: NSAttributedString
  private let framesetter: CTFramesetter

  fileprivate init?(
    text: String,
    configuration: TextLayoutConfiguration,
    cancellation: PaginationCancellation
  ) {
    self.string = text
    self.configuration = configuration
    guard !cancellation.isCancelled else { return nil }

    let font =
      NSFont(name: configuration.fontName, size: configuration.fontSize)
      ?? NSFont(name: "NanumMyeongjo", size: configuration.fontSize)
      ?? NSFont.systemFont(ofSize: configuration.fontSize)
    let ink = NSColor(
      calibratedRed: 42.0 / 255.0,
      green: 33.0 / 255.0,
      blue: 24.0 / 255.0,
      alpha: 1
    )
    let mutableText = NSMutableAttributedString(
      string: text,
      attributes: [
        .font: font,
        .foregroundColor: ink,
        .kern: configuration.letterSpacing,
        NSAttributedString.Key(kCTLanguageAttributeName as String): "ko",
      ]
    )
    guard !cancellation.isCancelled,
      Self.applyParagraphStyles(
        to: mutableText,
        font: font,
        configuration: configuration,
        cancellation: cancellation
      ),
      Self.fitFixedWidthClosingPadding(
        in: mutableText,
        pageWidth: configuration.pageWidth,
        cancellation: cancellation
      ),
      Self.applyHangulWordPriorityWrap(
        to: mutableText,
        pageWidth: configuration.pageWidth,
        cancellation: cancellation
      ),
      !cancellation.isCancelled
    else { return nil }
    // The attributed string is fully prepared before it escapes this initializer,
    // so retaining it as an immutable reference avoids another document-sized copy.
    attributedText = mutableText
    textLength = attributedText.length
    guard !cancellation.isCancelled else { return nil }
    framesetter = CTFramesetterCreateWithAttributedString(attributedText)
  }

  private static func applyParagraphStyles(
    to text: NSMutableAttributedString,
    font: NSFont,
    configuration: TextLayoutConfiguration,
    cancellation: PaginationCancellation
  ) -> Bool {
    let source = text.string as NSString
    guard source.length > 0 else { return true }

    let defaultStyle = NSMutableParagraphStyle()
    defaultStyle.lineHeightMultiple = configuration.lineHeightMultiple
    defaultStyle.paragraphSpacing = configuration.paragraphSpacing
    defaultStyle.lineBreakMode = .byWordWrapping
    defaultStyle.lineBreakStrategy = [.hangulWordPriority]
    defaultStyle.firstLineHeadIndent = 0
    defaultStyle.headIndent = 0
    text.addAttribute(
      .paragraphStyle,
      value: defaultStyle,
      range: NSRange(location: 0, length: source.length)
    )

    var cursor = 0
    while cursor < source.length {
      guard !cancellation.isCancelled else { return false }
      var paragraphStart = 0
      var paragraphEnd = 0
      var contentsEnd = 0
      source.getParagraphStart(
        &paragraphStart,
        end: &paragraphEnd,
        contentsEnd: &contentsEnd,
        for: NSRange(location: cursor, length: 0)
      )

      let contentRange = NSRange(
        location: paragraphStart,
        length: max(0, contentsEnd - paragraphStart)
      )
      let leadingRange = leadingHorizontalWhitespaceRange(in: source, range: contentRange)
      if leadingRange.length > 0 {
        let leadingText = source.substring(with: leadingRange)
        let measuredIndent = (leadingText as NSString).size(
          withAttributes: [
            .font: font,
            .kern: configuration.letterSpacing,
          ]
        ).width
        let paragraphStyle = defaultStyle.mutableCopy() as! NSMutableParagraphStyle
        paragraphStyle.headIndent = min(
          measuredIndent,
          max(0, configuration.pageWidth * 0.35)
        )

        let styleRange = NSRange(
          location: paragraphStart,
          length: max(0, paragraphEnd - paragraphStart)
        )
        if styleRange.length > 0 {
          text.addAttribute(.paragraphStyle, value: paragraphStyle, range: styleRange)
        }
      }

      guard paragraphEnd > cursor else { break }
      cursor = paragraphEnd
    }
    return true
  }

  private static func leadingHorizontalWhitespaceRange(
    in source: NSString,
    range: NSRange
  ) -> NSRange {
    var end = range.location
    let upperBound = NSMaxRange(range)
    while end < upperBound {
      let character = source.character(at: end)
      guard
        let scalar = UnicodeScalar(character),
        CharacterSet.whitespaces.contains(scalar)
      else { break }
      end += 1
    }
    return NSRange(location: range.location, length: end - range.location)
  }

  private static func fitFixedWidthClosingPadding(
    in text: NSMutableAttributedString,
    pageWidth: CGFloat,
    cancellation: PaginationCancellation
  ) -> Bool {
    let source = text.string as NSString
    guard source.length > 0 else { return true }
    let closingCharacters = CharacterSet(charactersIn: "』」】》〉〕）)]}")

    var cursor = 0
    while cursor < source.length {
      guard !cancellation.isCancelled else { return false }
      var paragraphStart = 0
      var paragraphEnd = 0
      var contentsEnd = 0
      source.getParagraphStart(
        &paragraphStart,
        end: &paragraphEnd,
        contentsEnd: &contentsEnd,
        for: NSRange(location: cursor, length: 0)
      )

      var closingLocation = contentsEnd - 1
      while closingLocation >= paragraphStart {
        let character = source.character(at: closingLocation)
        guard
          let scalar = UnicodeScalar(character),
          CharacterSet.whitespaces.contains(scalar)
        else { break }
        closingLocation -= 1
      }

      if closingLocation >= paragraphStart,
        UnicodeScalar(source.character(at: closingLocation)).map(closingCharacters.contains) == true
      {
        var paddingStart = closingLocation
        while paddingStart > paragraphStart {
          let previous = source.character(at: paddingStart - 1)
          guard
            let scalar = UnicodeScalar(previous),
            CharacterSet.whitespaces.contains(scalar)
          else { break }
          paddingStart -= 1
        }
        let paddingRange = NSRange(
          location: paddingStart,
          length: closingLocation - paddingStart
        )
        if paddingRange.length >= 8 {
          let prefixRange = NSRange(
            location: paragraphStart,
            length: paddingStart - paragraphStart
          )
          let closingRange = NSRange(location: closingLocation, length: 1)
          let prefixWidth = typographicWidth(in: text, range: prefixRange)
          let closingWidth = typographicWidth(in: text, range: closingRange)
          let paddingWidth = typographicWidth(in: text, range: paddingRange)
          let availablePaddingWidth = max(0, pageWidth - prefixWidth - closingWidth)

          if paddingWidth > availablePaddingWidth,
            availablePaddingWidth > 0,
            let sourceFont = text.attribute(
              .font,
              at: paddingStart,
              effectiveRange: nil
            ) as? NSFont
          {
            let scale = min(1, availablePaddingWidth / paddingWidth)
            let fittedFont =
              NSFont(
                descriptor: sourceFont.fontDescriptor,
                size: max(0.1, sourceFont.pointSize * scale)
              ) ?? NSFont.systemFont(ofSize: max(0.1, sourceFont.pointSize * scale))
            text.addAttributes(
              [.font: fittedFont, .kern: 0],
              range: paddingRange
            )
          }
        }
      }

      guard paragraphEnd > cursor else { break }
      cursor = paragraphEnd
    }
    return true
  }

  private static func typographicWidth(
    in text: NSAttributedString,
    range: NSRange
  ) -> CGFloat {
    guard range.length > 0 else { return 0 }
    let line = CTLineCreateWithAttributedString(text.attributedSubstring(from: range))
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
  }

  private static func applyHangulWordPriorityWrap(
    to text: NSMutableAttributedString,
    pageWidth: CGFloat,
    cancellation: PaginationCancellation
  ) -> Bool {
    guard text.length > 0, pageWidth > 0 else { return true }
    guard !cancellation.isCancelled else { return false }
    // Mutations are deferred until every break location has been measured, so the
    // typesetter can safely use the existing attributed string without a copy.
    let source = text.string as NSString
    let typesetter = CTTypesetterCreateWithAttributedString(text)
    var breakLocations: [Int] = []
    breakLocations.reserveCapacity(max(16, source.length / 120))

    var cursor = 0
    while cursor < source.length {
      guard !cancellation.isCancelled else { return false }
      var paragraphStart = 0
      var paragraphEnd = 0
      var contentsEnd = 0
      source.getParagraphStart(
        &paragraphStart,
        end: &paragraphEnd,
        contentsEnd: &contentsEnd,
        for: NSRange(location: cursor, length: 0)
      )

      let paragraphStyle =
        text.attribute(
          .paragraphStyle,
          at: paragraphStart,
          effectiveRange: nil
        ) as? NSParagraphStyle
      let continuationIndent = paragraphStyle?.headIndent ?? 0
      let firstContentLocation = NSMaxRange(
        leadingHorizontalWhitespaceRange(
          in: source,
          range: NSRange(
            location: paragraphStart,
            length: max(0, contentsEnd - paragraphStart)
          )
        )
      )

      var lineStart = paragraphStart
      var isFirstLine = true
      while lineStart < contentsEnd {
        guard !cancellation.isCancelled else { return false }
        let availableWidth = max(
          16,
          pageWidth - (isFirstLine ? 0 : continuationIndent)
        )
        let proposedLength = CTTypesetterSuggestClusterBreak(
          typesetter,
          lineStart,
          Double(availableWidth)
        )
        let safeLength = max(1, min(proposedLength, contentsEnd - lineStart))
        let proposedEnd = lineStart + safeLength
        guard proposedEnd < contentsEnd else { break }

        if let breakLocation = lastBreakableWhitespace(
          in: source,
          from: lineStart,
          before: proposedEnd,
          excludingBefore: max(lineStart, firstContentLocation)
        ) {
          breakLocations.append(breakLocation)
          lineStart = breakLocation + 1
        } else {
          lineStart = proposedEnd
        }
        isFirstLine = false
      }

      guard paragraphEnd > cursor else { break }
      cursor = paragraphEnd
    }

    for location in breakLocations {
      guard !cancellation.isCancelled else { return false }
      text.mutableString.replaceCharacters(
        in: NSRange(location: location, length: 1),
        with: "\u{2028}"
      )
    }
    return true
  }

  private static func lastBreakableWhitespace(
    in source: NSString,
    from lineStart: Int,
    before proposedEnd: Int,
    excludingBefore minimumLocation: Int
  ) -> Int? {
    guard proposedEnd > lineStart else { return nil }
    var location = proposedEnd - 1
    while location >= minimumLocation {
      let character = source.character(at: location)
      if character == 0x20 || character == 0x09 || character == 0x3000 {
        return location
      }
      location -= 1
    }
    return nil
  }

  public func draw(page: PageRange, in rect: CGRect, context: CGContext) {
    guard page.location >= 0, page.location <= textLength else { return }
    let path = CGPath(rect: rect, transform: nil)
    let frame = CTFramesetterCreateFrame(
      framesetter,
      CFRange(location: page.location, length: page.length),
      path,
      nil
    )
    CTFrameDraw(frame, context)
  }

  public func visibleText(for pages: [PageRange]) -> String {
    let source = string as NSString
    return pages.compactMap { page in
      guard page.location >= 0, page.upperBound <= source.length else { return nil }
      return source.substring(with: page.nsRange)
    }.joined(separator: "\n")
  }

  func layoutAttribute(_ key: NSAttributedString.Key, at location: Int) -> Any? {
    guard attributedText.length > 0 else { return nil }
    let safeLocation = min(max(0, location), attributedText.length - 1)
    return attributedText.attribute(key, at: safeLocation, effectiveRange: nil)
  }

  fileprivate func visibleRange(startingAt start: Int) -> PageRange {
    guard textLength > 0 else { return PageRange(location: 0, length: 0) }

    let safeStart = min(max(0, start), textLength - 1)
    let path = CGPath(
      rect: CGRect(
        x: 0,
        y: 0,
        width: max(16, configuration.pageWidth),
        height: max(16, configuration.pageHeight)
      ),
      transform: nil
    )
    let frame = CTFramesetterCreateFrame(
      framesetter,
      CFRange(location: safeStart, length: 0),
      path,
      nil
    )
    let visible = CTFrameGetVisibleStringRange(frame)
    var length = visible.length

    if length <= 0 {
      let source = attributedText.string as NSString
      length = source.rangeOfComposedCharacterSequence(at: safeStart).length
    }

    length = min(max(1, length), textLength - safeStart)
    let proposedEnd = safeStart + length
    if proposedEnd < textLength {
      let source = attributedText.string as NSString
      let sequence = source.rangeOfComposedCharacterSequence(at: proposedEnd - 1)
      if NSMaxRange(sequence) > proposedEnd, sequence.location > safeStart {
        length = sequence.location - safeStart
      }
    }
    return PageRange(location: safeStart, length: max(1, length))
  }
}

public enum PaginationEngine {
  public typealias BatchHandler = (
    _ layout: TextLayout, _ newPages: [PageRange], _ isComplete: Bool
  ) -> Void

  public static func paginate(
    text: String,
    configuration: TextLayoutConfiguration,
    cancellation: PaginationCancellation,
    batchSize: Int = 16,
    onBatch: BatchHandler
  ) {
    guard !cancellation.isCancelled else { return }
    guard
      let layout = TextLayout(
        text: text,
        configuration: configuration,
        cancellation: cancellation
      ),
      !cancellation.isCancelled
    else { return }
    if layout.textLength == 0 {
      guard !cancellation.isCancelled else { return }
      onBatch(layout, [PageRange(location: 0, length: 0)], true)
      return
    }

    var start = 0
    var pending: [PageRange] = []
    pending.reserveCapacity(max(1, batchSize))
    var publishedFirstPage = false

    while start < layout.textLength {
      if cancellation.isCancelled { return }

      let page = layout.visibleRange(startingAt: start)
      pending.append(page)
      start = page.upperBound

      if !publishedFirstPage {
        publishedFirstPage = true
        onBatch(layout, pending, start >= layout.textLength)
        pending.removeAll(keepingCapacity: true)
      } else if pending.count >= max(1, batchSize) {
        onBatch(layout, pending, start >= layout.textLength)
        pending.removeAll(keepingCapacity: true)
      }
    }

    if !pending.isEmpty, !cancellation.isCancelled {
      onBatch(layout, pending, true)
    }
  }

  public static func pageIndex(containing anchor: Int, in pages: [PageRange]) -> Int? {
    guard !pages.isEmpty else { return nil }
    let clampedAnchor = max(0, anchor)
    var low = 0
    var high = pages.count - 1

    while low <= high {
      let middle = low + (high - low) / 2
      let page = pages[middle]
      if clampedAnchor < page.location {
        high = middle - 1
      } else if clampedAnchor >= page.upperBound, page.length > 0 {
        low = middle + 1
      } else {
        return middle
      }
    }

    if clampedAnchor >= pages[pages.count - 1].upperBound {
      return pages.count - 1
    }
    return nil
  }

  public static func anchor(forProgress progress: Double, textLength: Int) -> Int {
    guard textLength > 0 else { return 0 }
    let clampedProgress = min(max(progress, 0), 1)
    return Int((Double(textLength) * clampedProgress).rounded())
  }
}
