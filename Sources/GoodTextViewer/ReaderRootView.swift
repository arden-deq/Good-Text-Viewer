import AppKit

private let parchmentColor = NSColor(
  calibratedRed: 226.0 / 255.0,
  green: 204.0 / 255.0,
  blue: 161.0 / 255.0,
  alpha: 1
)
private let inkColor = NSColor(
  calibratedRed: 54.0 / 255.0,
  green: 42.0 / 255.0,
  blue: 29.0 / 255.0,
  alpha: 1
)
private let accentColor = NSColor(
  calibratedRed: 147.0 / 255.0,
  green: 95.0 / 255.0,
  blue: 55.0 / 255.0,
  alpha: 1
)

final class ModeButton: NSButton {
  var isModeSelected = false {
    didSet { updateAppearance() }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    isBordered = false
    imagePosition = .imageOnly
    wantsLayer = true
    layer?.cornerRadius = 9
    focusRingType = .default
    updateAppearance()
  }

  required init?(coder: NSCoder) {
    nil
  }

  private func updateAppearance() {
    layer?.backgroundColor = (isModeSelected ? accentColor : .clear).cgColor
    contentTintColor = isModeSelected ? parchmentColor : inkColor.withAlphaComponent(0.82)
    state = isModeSelected ? .on : .off
    setAccessibilityValue(isModeSelected ? "선택됨" : "선택 안 됨")
  }
}

final class ProgressLineView: NSView {
  var progress: Double = 0 {
    didSet {
      progress = min(max(progress, 0), 1)
      setAccessibilityValue(Int((progress * 100).rounded()))
      if abs(progress - oldValue) > 0.000_001 {
        NSAccessibility.post(element: self, notification: .valueChanged)
      }
      needsDisplay = true
    }
  }
  var isSeekEnabled = false {
    didSet {
      guard isSeekEnabled != oldValue else { return }
      setAccessibilityEnabled(isSeekEnabled)
      if !isSeekEnabled { isScrubbing = false }
      window?.invalidateCursorRects(for: self)
      window?.recalculateKeyViewLoop()
      needsDisplay = true
    }
  }
  var onSeek: ((Double, Bool) -> Void)?
  var onStepBackward: (() -> Void)?
  var onStepForward: (() -> Void)?

  private var isPointerInside = false
  private var isScrubbing = false
  private var pointerTrackingArea: NSTrackingArea?

  override var acceptsFirstResponder: Bool { isSeekEnabled }
  override var canBecomeKeyView: Bool { isSeekEnabled }
  override var isOpaque: Bool { false }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let pointerTrackingArea {
      removeTrackingArea(pointerTrackingArea)
    }
    let trackingArea = NSTrackingArea(
      rect: bounds,
      options: [.activeInKeyWindow, .mouseEnteredAndExited],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(trackingArea)
    pointerTrackingArea = trackingArea
  }

  override func resetCursorRects() {
    super.resetCursorRects()
    guard isSeekEnabled else { return }
    addCursorRect(bounds, cursor: .resizeLeftRight)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let horizontalInset: CGFloat = 5
    let lineRect = NSRect(
      x: horizontalInset,
      y: floor((bounds.height - 2) / 2),
      width: max(0, bounds.width - horizontalInset * 2),
      height: 2
    )
    inkColor.withAlphaComponent(0.14).setFill()
    NSBezierPath(roundedRect: lineRect, xRadius: 1, yRadius: 1).fill()

    let clampedProgress = min(max(progress, 0), 1)
    let filledRect = NSRect(
      x: lineRect.minX,
      y: lineRect.minY,
      width: lineRect.width * clampedProgress,
      height: lineRect.height
    )
    accentColor.withAlphaComponent(isSeekEnabled ? 0.92 : 0.42).setFill()
    NSBezierPath(roundedRect: filledRect, xRadius: 1, yRadius: 1).fill()

    guard isSeekEnabled else { return }
    let thumbRadius: CGFloat = isPointerInside || isScrubbing ? 5 : 3.5
    let thumbCenterX = lineRect.minX + lineRect.width * clampedProgress
    let thumbRect = NSRect(
      x: thumbCenterX - thumbRadius,
      y: lineRect.midY - thumbRadius,
      width: thumbRadius * 2,
      height: thumbRadius * 2
    )
    parchmentColor.setFill()
    NSBezierPath(ovalIn: thumbRect.insetBy(dx: -1, dy: -1)).fill()
    accentColor.setFill()
    NSBezierPath(ovalIn: thumbRect).fill()
  }

  override func mouseEntered(with event: NSEvent) {
    isPointerInside = true
    needsDisplay = true
  }

  override func mouseExited(with event: NSEvent) {
    isPointerInside = false
    needsDisplay = true
  }

  override func mouseDown(with event: NSEvent) {
    guard isSeekEnabled else { return }
    window?.makeFirstResponder(self)
    isScrubbing = true
    seek(with: event, finished: false)
  }

  override func mouseDragged(with event: NSEvent) {
    guard isScrubbing else { return }
    seek(with: event, finished: false)
  }

  override func mouseUp(with event: NSEvent) {
    guard isScrubbing else { return }
    seek(with: event, finished: true)
    isScrubbing = false
    needsDisplay = true
  }

  override func keyDown(with event: NSEvent) {
    guard isSeekEnabled else {
      super.keyDown(with: event)
      return
    }
    switch event.keyCode {
    case 123:
      onStepBackward?()
    case 124:
      onStepForward?()
    case 115:
      updateProgress(0, finished: true)
    case 119:
      updateProgress(1, finished: true)
    default:
      super.keyDown(with: event)
    }
  }

  override func accessibilityPerformIncrement() -> Bool {
    guard isSeekEnabled else { return false }
    onStepForward?()
    return true
  }

  override func accessibilityPerformDecrement() -> Bool {
    guard isSeekEnabled else { return false }
    onStepBackward?()
    return true
  }

  private func seek(with event: NSEvent, finished: Bool) {
    let horizontalInset: CGFloat = 5
    let trackWidth = max(1, bounds.width - horizontalInset * 2)
    let location = convert(event.locationInWindow, from: nil)
    updateProgress((location.x - horizontalInset) / trackWidth, finished: finished)
  }

  private func updateProgress(_ value: Double, finished: Bool) {
    progress = min(max(value, 0), 1)
    onSeek?(progress, finished)
  }
}

final class ReaderRootView: NSView {
  let canvas = ReaderCanvasView()
  let titleLabel = NSTextField(labelWithString: "Good Text Viewer")
  let openButton = NSButton(title: "⌘O  열기", target: nil, action: nil)
  let singlePageButton = ModeButton(frame: .zero)
  let spreadButton = ModeButton(frame: .zero)
  let increaseFontButton = NSButton(frame: .zero)
  let decreaseFontButton = NSButton(frame: .zero)
  let increaseLetterSpacingButton = NSButton(frame: .zero)
  let decreaseLetterSpacingButton = NSButton(frame: .zero)
  let fontSizeLabel = NSTextField(labelWithString: "18")
  let letterSpacingLabel = NSTextField(labelWithString: "0.0")
  let previousButton = NSButton(frame: .zero)
  let nextButton = NSButton(frame: .zero)
  let progressLabel = NSTextField(labelWithString: "0%")
  let progressIndicator = ProgressLineView()
  let spinner = NSProgressIndicator()

  var onOpenURL: ((URL) -> Void)?
  var onGeometryChanged: ((CGSize) -> Void)?
  var onSeekProgress: ((Double, Bool) -> Void)?
  var onProgressStepBackward: (() -> Void)?
  var onProgressStepForward: (() -> Void)?

  private let header = NSView()
  private let rail = NSView()
  private let bottomControls = NSView()
  private var lastReportedCanvasSize = CGSize.zero

  override var acceptsFirstResponder: Bool { true }
  override var isOpaque: Bool { true }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = parchmentColor.cgColor
    registerForDraggedTypes([.fileURL])
    buildInterface()
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func layout() {
    super.layout()
    let size = canvas.bounds.size
    guard
      abs(size.width - lastReportedCanvasSize.width) > 1
        || abs(size.height - lastReportedCanvasSize.height) > 1
    else { return }
    lastReportedCanvasSize = size
    onGeometryChanged?(size)
  }

  func updateMode(_ mode: ReaderPageMode) {
    singlePageButton.isModeSelected = mode == .single
    spreadButton.isModeSelected = mode == .spread
  }

  func updateFontSize(_ size: CGFloat) {
    fontSizeLabel.stringValue = String(Int(size.rounded()))
    fontSizeLabel.setAccessibilityLabel("글자 크기 \(Int(size.rounded()))포인트")
  }

  func updateLetterSpacing(_ spacing: CGFloat) {
    letterSpacingLabel.stringValue = String(format: "%.1f", Double(spacing))
    letterSpacingLabel.setAccessibilityLabel(
      String(format: "자간 %.1f포인트", Double(spacing))
    )
  }

  func updateProgress(percent: Double, canGoPrevious: Bool, canGoNext: Bool) {
    previewProgress(percent: percent)
    previousButton.isEnabled = canGoPrevious
    nextButton.isEnabled = canGoNext
  }

  func disablePageNavigation() {
    previousButton.isEnabled = false
    nextButton.isEnabled = false
  }

  func previewProgress(percent: Double) {
    let clampedPercent = min(max(percent, 0), 1)
    let wholePercent = Int((clampedPercent * 100).rounded())
    progressLabel.stringValue = "\(wholePercent)%"
    progressLabel.setAccessibilityLabel("진행률 \(wholePercent)퍼센트")
    progressIndicator.progress = clampedPercent
  }

  func setProgressSeekingEnabled(_ enabled: Bool) {
    progressIndicator.isSeekEnabled = enabled
  }

  func setLoading(_ loading: Bool) {
    if loading {
      spinner.isHidden = false
      spinner.startAnimation(nil)
    } else {
      spinner.stopAnimation(nil)
      spinner.isHidden = true
    }
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    droppedTXTURL(from: sender) == nil ? [] : .copy
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let url = droppedTXTURL(from: sender) else { return false }
    onOpenURL?(url)
    return true
  }

  private func droppedTXTURL(from sender: NSDraggingInfo) -> URL? {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    guard
      let urls = sender.draggingPasteboard.readObjects(
        forClasses: [NSURL.self],
        options: options
      ) as? [URL], urls.count == 1
    else {
      return nil
    }
    let url = urls[0]
    return url.pathExtension.caseInsensitiveCompare("txt") == .orderedSame ? url : nil
  }

  private func buildInterface() {
    for child in [canvas, header, rail, bottomControls, spinner] {
      child.translatesAutoresizingMaskIntoConstraints = false
      addSubview(child)
    }

    NSLayoutConstraint.activate([
      canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
      canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
      canvas.topAnchor.constraint(equalTo: header.bottomAnchor),
      canvas.bottomAnchor.constraint(equalTo: bottomAnchor),

      header.leadingAnchor.constraint(equalTo: leadingAnchor),
      header.trailingAnchor.constraint(equalTo: trailingAnchor),
      header.topAnchor.constraint(equalTo: topAnchor),
      header.heightAnchor.constraint(equalToConstant: 64),

      rail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
      rail.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 8),
      rail.widthAnchor.constraint(equalToConstant: 60),
      rail.topAnchor.constraint(greaterThanOrEqualTo: header.bottomAnchor, constant: 18),
      rail.bottomAnchor.constraint(
        lessThanOrEqualTo: bottomControls.topAnchor,
        constant: -12
      ),

      bottomControls.centerXAnchor.constraint(equalTo: centerXAnchor, constant: -28),
      bottomControls.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
      bottomControls.widthAnchor.constraint(equalToConstant: 460),
      bottomControls.heightAnchor.constraint(equalToConstant: 54),

      spinner.centerXAnchor.constraint(equalTo: centerXAnchor, constant: -28),
      spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])

    buildHeader()
    buildRail()
    buildBottomControls()

    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.isDisplayedWhenStopped = false
    spinner.isHidden = true
  }

  private func buildHeader() {
    let separator = NSBox()
    separator.boxType = .separator
    separator.translatesAutoresizingMaskIntoConstraints = false
    header.addSubview(separator)

    titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
    titleLabel.textColor = inkColor
    titleLabel.lineBreakMode = .byTruncatingMiddle
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    header.addSubview(titleLabel)

    openButton.isBordered = false
    openButton.font = .systemFont(ofSize: 14, weight: .regular)
    openButton.contentTintColor = inkColor
    openButton.focusRingType = .default
    openButton.setAccessibilityLabel("파일 열기")
    openButton.translatesAutoresizingMaskIntoConstraints = false
    header.addSubview(openButton)

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 84),
      titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor, constant: 2),
      titleLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: openButton.leadingAnchor, constant: -20),
      openButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -28),
      openButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
      separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
      separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),
    ])
  }

  private func buildRail() {
    rail.wantsLayer = true
    rail.layer?.backgroundColor =
      NSColor(
        calibratedRed: 238.0 / 255.0,
        green: 218.0 / 255.0,
        blue: 181.0 / 255.0,
        alpha: 0.88
      ).cgColor
    rail.layer?.borderColor = inkColor.withAlphaComponent(0.18).cgColor
    rail.layer?.borderWidth = 1
    rail.layer?.cornerRadius = 11

    configureSymbolButton(singlePageButton, symbol: "doc.plaintext", label: "한쪽 보기")
    configureSymbolButton(spreadButton, symbol: "book.closed", label: "두쪽 보기")
    configureSymbolButton(increaseFontButton, symbol: "plus", label: "글자 크게")
    configureSymbolButton(decreaseFontButton, symbol: "minus", label: "글자 작게")
    configureSymbolButton(
      increaseLetterSpacingButton,
      symbol: "plus",
      label: "자간 넓게"
    )
    configureSymbolButton(
      decreaseLetterSpacingButton,
      symbol: "minus",
      label: "자간 좁게"
    )

    fontSizeLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .medium)
    fontSizeLabel.textColor = inkColor
    fontSizeLabel.alignment = .center
    letterSpacingLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
    letterSpacingLabel.textColor = inkColor
    letterSpacingLabel.alignment = .center

    let modeSeparator = makeRailSeparator()
    let settingSeparator = makeRailSeparator()
    let fontHeader = makeRailSectionIcon(symbol: "textformat.size", label: "글자 크기")
    let spacingHeader = makeRailSectionIcon(symbol: "arrow.left.and.right", label: "자간")
    let fontValue = centeredValueContainer(for: fontSizeLabel)
    let spacingValue = centeredValueContainer(for: letterSpacingLabel)

    let stack = NSStackView(views: [
      singlePageButton,
      spreadButton,
      modeSeparator,
      fontHeader,
      increaseFontButton,
      fontValue,
      decreaseFontButton,
      settingSeparator,
      spacingHeader,
      increaseLetterSpacingButton,
      spacingValue,
      decreaseLetterSpacingButton,
    ])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 2
    stack.translatesAutoresizingMaskIntoConstraints = false
    rail.addSubview(stack)

    for button in [singlePageButton, spreadButton] {
      button.widthAnchor.constraint(equalToConstant: 44).isActive = true
      button.heightAnchor.constraint(equalToConstant: 42).isActive = true
    }
    for button in [
      increaseFontButton,
      decreaseFontButton,
      increaseLetterSpacingButton,
      decreaseLetterSpacingButton,
    ] {
      button.widthAnchor.constraint(equalToConstant: 44).isActive = true
      button.heightAnchor.constraint(equalToConstant: 34).isActive = true
    }
    for separator in [modeSeparator, settingSeparator] {
      separator.widthAnchor.constraint(equalToConstant: 30).isActive = true
      separator.heightAnchor.constraint(equalToConstant: 8).isActive = true
    }
    for header in [fontHeader, spacingHeader] {
      header.widthAnchor.constraint(equalToConstant: 44).isActive = true
      header.heightAnchor.constraint(equalToConstant: 20).isActive = true
    }
    for value in [fontValue, spacingValue] {
      value.widthAnchor.constraint(equalToConstant: 44).isActive = true
      value.heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: rail.leadingAnchor, constant: 6),
      stack.trailingAnchor.constraint(equalTo: rail.trailingAnchor, constant: -6),
      stack.topAnchor.constraint(equalTo: rail.topAnchor, constant: 6),
      stack.bottomAnchor.constraint(equalTo: rail.bottomAnchor, constant: -6),
    ])
  }

  private func buildBottomControls() {
    configureSymbolButton(previousButton, symbol: "chevron.left", label: "이전 페이지")
    configureSymbolButton(nextButton, symbol: "chevron.right", label: "다음 페이지")
    previousButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
    nextButton.widthAnchor.constraint(equalToConstant: 52).isActive = true

    progressLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
    progressLabel.textColor = inkColor.withAlphaComponent(0.82)
    progressLabel.alignment = .center
    progressLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true

    let row = NSStackView(views: [previousButton, progressLabel, nextButton])
    row.orientation = .horizontal
    row.distribution = .equalSpacing
    row.alignment = .centerY
    row.translatesAutoresizingMaskIntoConstraints = false

    progressIndicator.translatesAutoresizingMaskIntoConstraints = false
    progressIndicator.setAccessibilityElement(true)
    progressIndicator.setAccessibilityRole(.slider)
    progressIndicator.setAccessibilityLabel("읽기 진행률")
    progressIndicator.setAccessibilityHelp("드래그하거나 방향키로 읽을 위치를 이동합니다")
    progressIndicator.setAccessibilityMinValue(0)
    progressIndicator.setAccessibilityMaxValue(100)
    progressIndicator.onSeek = { [weak self] progress, finished in
      self?.onSeekProgress?(progress, finished)
    }
    progressIndicator.onStepBackward = { [weak self] in
      self?.onProgressStepBackward?()
    }
    progressIndicator.onStepForward = { [weak self] in
      self?.onProgressStepForward?()
    }

    bottomControls.addSubview(row)
    bottomControls.addSubview(progressIndicator)
    NSLayoutConstraint.activate([
      row.leadingAnchor.constraint(equalTo: bottomControls.leadingAnchor, constant: 95),
      row.trailingAnchor.constraint(equalTo: bottomControls.trailingAnchor, constant: -95),
      row.topAnchor.constraint(equalTo: bottomControls.topAnchor),
      row.heightAnchor.constraint(equalToConstant: 34),
      progressIndicator.leadingAnchor.constraint(equalTo: bottomControls.leadingAnchor),
      progressIndicator.trailingAnchor.constraint(equalTo: bottomControls.trailingAnchor),
      progressIndicator.bottomAnchor.constraint(equalTo: bottomControls.bottomAnchor),
      progressIndicator.heightAnchor.constraint(equalToConstant: 18),
    ])
  }

  private func makeRailSeparator() -> NSBox {
    let separator = NSBox()
    separator.boxType = .separator
    return separator
  }

  private func makeRailSectionIcon(symbol: String, label: String) -> NSImageView {
    let imageView = NSImageView()
    imageView.image = NSImage(
      systemSymbolName: symbol,
      accessibilityDescription: label
    )
    imageView.contentTintColor = inkColor.withAlphaComponent(0.66)
    imageView.imageScaling = .scaleProportionallyDown
    imageView.setAccessibilityElement(true)
    imageView.setAccessibilityRole(.image)
    imageView.setAccessibilityLabel(label)
    return imageView
  }

  private func centeredValueContainer(for label: NSTextField) -> NSView {
    let container = NSView()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.setContentHuggingPriority(.required, for: .vertical)
    label.setContentCompressionResistancePriority(.required, for: .vertical)
    container.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      label.widthAnchor.constraint(equalTo: container.widthAnchor),
    ])
    return container
  }

  private func configureSymbolButton(_ button: NSButton, symbol: String, label: String) {
    button.isBordered = false
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    button.imagePosition = .imageOnly
    button.contentTintColor = inkColor.withAlphaComponent(0.82)
    button.focusRingType = .default
    button.setAccessibilityLabel(label)
  }
}
