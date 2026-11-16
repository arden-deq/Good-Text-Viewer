import AppKit
import GoodTextViewerCore

final class ReaderCanvasView: NSView {
  private(set) var textLayout: TextLayout?
  private(set) var pages: [PageRange] = []
  private(set) var pageMode: ReaderPageMode = .single
  var placeholderText = "TXT 파일을 열어주세요" {
    didSet { needsDisplay = true }
  }

  override var acceptsFirstResponder: Bool { true }
  override var isOpaque: Bool { false }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
    setAccessibilityLabel("본문")
  }

  required init?(coder: NSCoder) {
    nil
  }

  func pageSize(for mode: ReaderPageMode) -> CGSize {
    let height = max(180, bounds.height - 150)
    switch mode {
    case .single:
      return CGSize(
        width: min(660, max(320, bounds.width - 360)),
        height: height
      )
    case .spread:
      let width = (bounds.width - 240 - 56) / 2
      return CGSize(
        width: min(540, max(250, width)),
        height: height
      )
    }
  }

  func show(
    layout: TextLayout,
    pages: [PageRange],
    mode: ReaderPageMode
  ) {
    textLayout = layout
    self.pages = pages
    self.pageMode = mode
    placeholderText = ""
    updateAccessibilityText()
    needsDisplay = true
  }

  func clear(placeholder: String) {
    textLayout = nil
    pages = []
    placeholderText = placeholder
    setAccessibilityValue(placeholder)
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    guard let textLayout, !pages.isEmpty,
      let context = NSGraphicsContext.current?.cgContext
    else {
      drawPlaceholder()
      return
    }

    let rects = pageRects(
      pageSize: CGSize(
        width: textLayout.configuration.pageWidth,
        height: textLayout.configuration.pageHeight
      ))

    context.saveGState()
    context.setShouldAntialias(true)
    context.setShouldSmoothFonts(true)
    for (page, rect) in zip(pages, rects) {
      textLayout.draw(page: page, in: rect, context: context)
    }
    context.restoreGState()
  }

  private func pageRects(pageSize: CGSize) -> [CGRect] {
    let rightReserved: CGFloat = 112
    let usableWidth = max(pageSize.width, bounds.width - rightReserved)
    let bottom: CGFloat = 76

    switch pageMode {
    case .single:
      let x = max(42, (usableWidth - pageSize.width) / 2)
      return [CGRect(x: x, y: bottom, width: pageSize.width, height: pageSize.height)]
    case .spread:
      let gutter: CGFloat = 56
      let totalWidth = pageSize.width * 2 + gutter
      let startX = max(28, (usableWidth - totalWidth) / 2)
      return [
        CGRect(x: startX, y: bottom, width: pageSize.width, height: pageSize.height),
        CGRect(
          x: startX + pageSize.width + gutter, y: bottom, width: pageSize.width,
          height: pageSize.height),
      ]
    }
  }

  private func drawPlaceholder() {
    guard !placeholderText.isEmpty else { return }
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 15, weight: .regular),
      .foregroundColor: NSColor(
        calibratedRed: 88.0 / 255.0,
        green: 67.0 / 255.0,
        blue: 44.0 / 255.0,
        alpha: 0.72
      ),
    ]
    let size = placeholderText.size(withAttributes: attributes)
    let point = CGPoint(
      x: floor((bounds.width - size.width) / 2) - 24,
      y: floor((bounds.height - size.height) / 2)
    )
    placeholderText.draw(at: point, withAttributes: attributes)
  }

  private func updateAccessibilityText() {
    guard let textLayout else {
      setAccessibilityValue(placeholderText)
      return
    }
    setAccessibilityValue(textLayout.visibleText(for: pages))
  }
}
