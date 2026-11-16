import AppKit
import GoodTextViewerCore
import UniformTypeIdentifiers

final class ReaderViewController: NSViewController {
  private let rootView = ReaderRootView()
  private let preferences = ReaderPreferences.shared
  private let loadQueue = DispatchQueue(label: "com.goodtextviewer.load", qos: .userInitiated)
  private let paginationQueue = DispatchQueue(
    label: "com.goodtextviewer.pagination", qos: .userInitiated)

  private var document: LoadedTextDocument?
  private var documentRepairsLegacyHardWraps: Bool?
  private var requestedURL: URL?
  private var layout: TextLayout?
  private var pages: [PageRange] = []
  private var currentPageIndex = 0
  private var pageMode: ReaderPageMode
  private var fontSize: CGFloat
  private var letterSpacing: CGFloat
  private var pendingAnchor: Int?
  private var pendingSeekProgress: Double?
  private var pendingReloadProgress: Double?
  private var paginationComplete = false
  private var isAwaitingPaginationLayout = false
  private var loadGeneration = 0
  private var paginationGeneration = 0
  private var loadCancellation: PaginationCancellation?
  private var paginationCancellation: PaginationCancellation?
  private var resizeWorkItem: DispatchWorkItem?
  private var eventMonitor: Any?

  init() {
    pageMode = preferences.pageMode
    fontSize = preferences.fontSize
    letterSpacing = preferences.letterSpacing
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func loadView() {
    view = rootView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    wireActions()
    rootView.updateMode(pageMode)
    rootView.updateFontSize(fontSize)
    rootView.updateLetterSpacing(letterSpacing)
    rootView.setProgressSeekingEnabled(false)
    rootView.updateProgress(percent: 0, canGoPrevious: false, canGoNext: false)
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    installEventMonitorIfNeeded()
    view.window?.makeFirstResponder(rootView.canvas)
  }

  deinit {
    loadCancellation?.cancel()
    paginationCancellation?.cancel()
    if let eventMonitor {
      NSEvent.removeMonitor(eventMonitor)
    }
  }

  func openPanel() {
    let panel = NSOpenPanel()
    panel.title = "TXT 파일 열기"
    panel.prompt = "열기"
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = [UTType(filenameExtension: "txt") ?? .plainText]

    guard let window = view.window else { return }
    panel.beginSheetModal(for: window) { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      self?.open(url: url)
    }
  }

  func open(url: URL) {
    pendingReloadProgress = nil
    cancelScheduledResizeReflow()
    loadCancellation?.cancel()
    let cancellation = PaginationCancellation()
    loadCancellation = cancellation
    loadGeneration += 1
    let generation = loadGeneration
    let normalizedURL = url.standardizedFileURL
    requestedURL = normalizedURL
    let repairsLegacyHardWraps = preferences.repairsLegacyHardWraps
    rootView.titleLabel.stringValue = normalizedURL.lastPathComponent
    rootView.canvas.placeholderText = document == nil ? "TXT 파일을 여는 중…" : ""
    rootView.setLoading(true)

    loadQueue.async { [weak self] in
      guard !cancellation.isCancelled else { return }
      let result: Result<LoadedTextDocument, Error>
      do {
        result = .success(
          try TextDocumentLoader.load(
            from: normalizedURL,
            repairsLegacyHardWraps: repairsLegacyHardWraps,
            cancellation: cancellation
          )
        )
      } catch {
        result = .failure(error)
      }

      guard !cancellation.isCancelled else { return }

      DispatchQueue.main.async {
        guard let self, generation == self.loadGeneration else { return }
        self.loadCancellation = nil
        self.rootView.setLoading(false)
        switch result {
        case .success(let loaded):
          self.install(document: loaded, repairsLegacyHardWraps: repairsLegacyHardWraps)
        case .failure(let error):
          if self.document == nil {
            self.rootView.canvas.clear(placeholder: "TXT 파일을 열어주세요")
            self.rootView.titleLabel.stringValue = "Good Text Viewer"
          } else if let document = self.document {
            self.rootView.titleLabel.stringValue = document.title
            self.view.window?.title = document.title
          }
          self.present(error: error)
        }
      }
    }
  }

  func restoreLastDocumentIfAvailable() {
    guard let path = preferences.lastDocumentPath else { return }
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    open(url: url)
  }

  func showSinglePage() {
    setPageMode(.single)
  }

  func showSpread() {
    setPageMode(.spread)
  }

  var repairsLegacyHardWraps: Bool {
    preferences.repairsLegacyHardWraps
  }

  @discardableResult
  func toggleLegacyHardWrapRepair() -> Bool {
    persistReadingPosition()
    let reloadURL = Self.preferredRepairReloadURL(
      requestedURL: requestedURL,
      documentURL: document?.url
    )
    let reloadProgress = Self.repairReloadProgress(
      documentURL: document?.url,
      reloadURL: reloadURL,
      anchor: currentAnchor,
      textLength: document.map { ($0.text as NSString).length }
    )
    let enabled = !preferences.repairsLegacyHardWraps
    preferences.repairsLegacyHardWraps = enabled
    if let url = reloadURL {
      open(url: url)
      pendingReloadProgress = reloadProgress
    }
    return enabled
  }

  func increaseFontSize() {
    setFontSize(fontSize + 1)
  }

  func decreaseFontSize() {
    setFontSize(fontSize - 1)
  }

  func increaseLetterSpacing() {
    setLetterSpacing(letterSpacing + 0.1)
  }

  func decreaseLetterSpacing() {
    setLetterSpacing(letterSpacing - 0.1)
  }

  func goToPreviousPage() {
    navigate(by: -pageMode.pageAdvance)
  }

  func goToNextPage() {
    navigate(by: pageMode.pageAdvance)
  }

  func goToBeginning() {
    guard !isAwaitingPaginationLayout, !pages.isEmpty else { return }
    pendingAnchor = nil
    pendingSeekProgress = nil
    currentPageIndex = 0
    applyVisiblePages(persistPosition: true)
  }

  func goToEnd() {
    guard !isAwaitingPaginationLayout, paginationComplete, !pages.isEmpty else { return }
    pendingAnchor = nil
    pendingSeekProgress = nil
    currentPageIndex = alignedPageIndex(pages.count - 1)
    applyVisiblePages(persistPosition: true)
  }

  func persistReadingPosition() {
    guard let document, let documentRepairsLegacyHardWraps else { return }
    if let pendingAnchor {
      preferences.save(
        anchor: pendingAnchor,
        for: document,
        repairsLegacyHardWraps: documentRepairsLegacyHardWraps
      )
    } else if pages.indices.contains(currentPageIndex) {
      preferences.save(
        anchor: pages[currentPageIndex].location,
        for: document,
        repairsLegacyHardWraps: documentRepairsLegacyHardWraps
      )
    }
  }

  static func preferredRepairReloadURL(requestedURL: URL?, documentURL: URL?) -> URL? {
    requestedURL ?? documentURL
  }

  static func repairReloadProgress(
    documentURL: URL?,
    reloadURL: URL?,
    anchor: Int,
    textLength: Int?
  ) -> Double? {
    guard
      let documentPath = documentURL?.standardizedFileURL.path,
      documentPath == reloadURL?.standardizedFileURL.path,
      let textLength
    else {
      return nil
    }
    guard textLength > 0 else { return 0 }
    return min(1, Double(max(0, anchor)) / Double(textLength))
  }

  private func wireActions() {
    rootView.openButton.target = self
    rootView.openButton.action = #selector(openButtonPressed)
    rootView.singlePageButton.target = self
    rootView.singlePageButton.action = #selector(singlePagePressed)
    rootView.spreadButton.target = self
    rootView.spreadButton.action = #selector(spreadPressed)
    rootView.increaseFontButton.target = self
    rootView.increaseFontButton.action = #selector(increaseFontPressed)
    rootView.decreaseFontButton.target = self
    rootView.decreaseFontButton.action = #selector(decreaseFontPressed)
    rootView.increaseLetterSpacingButton.target = self
    rootView.increaseLetterSpacingButton.action = #selector(increaseLetterSpacingPressed)
    rootView.decreaseLetterSpacingButton.target = self
    rootView.decreaseLetterSpacingButton.action = #selector(decreaseLetterSpacingPressed)
    rootView.previousButton.target = self
    rootView.previousButton.action = #selector(previousPressed)
    rootView.nextButton.target = self
    rootView.nextButton.action = #selector(nextPressed)
    rootView.onOpenURL = { [weak self] url in self?.open(url: url) }
    rootView.onGeometryChanged = { [weak self] _ in self?.scheduleResizeReflow() }
    rootView.onSeekProgress = { [weak self] progress, finished in
      self?.seek(toProgress: progress, finished: finished)
    }
    rootView.onProgressStepBackward = { [weak self] in
      self?.goToPreviousPage()
    }
    rootView.onProgressStepForward = { [weak self] in
      self?.goToNextPage()
    }
  }

  private func install(document: LoadedTextDocument, repairsLegacyHardWraps: Bool) {
    cancelScheduledResizeReflow()
    persistReadingPosition()
    self.document = document
    documentRepairsLegacyHardWraps = repairsLegacyHardWraps
    preferences.lastDocumentPath = document.url.path
    rootView.titleLabel.stringValue = document.title
    view.window?.title = document.title
    let anchor: Int
    if let progress = pendingReloadProgress {
      anchor = PaginationEngine.anchor(
        forProgress: progress,
        textLength: (document.text as NSString).length
      )
      pendingReloadProgress = nil
    } else {
      anchor = preferences.anchor(
        for: document,
        repairsLegacyHardWraps: repairsLegacyHardWraps
      )
    }
    rebuildPagination(preserving: anchor)
  }

  private func setPageMode(_ mode: ReaderPageMode) {
    guard pageMode != mode else { return }
    cancelScheduledResizeReflow()
    let anchor = currentAnchor
    pageMode = mode
    preferences.pageMode = mode
    rootView.updateMode(mode)
    if document != nil {
      rebuildPagination(preserving: anchor)
    }
  }

  private func setFontSize(_ size: CGFloat) {
    let clamped = min(max(size, 12), 36)
    guard clamped != fontSize else { return }
    cancelScheduledResizeReflow()
    let anchor = currentAnchor
    fontSize = clamped
    preferences.fontSize = clamped
    rootView.updateFontSize(clamped)
    if document != nil {
      rebuildPagination(preserving: anchor)
    }
  }

  private func setLetterSpacing(_ spacing: CGFloat) {
    let clamped = min(max((spacing * 10).rounded() / 10, -0.5), 2)
    guard clamped != letterSpacing else { return }
    cancelScheduledResizeReflow()
    let anchor = currentAnchor
    letterSpacing = clamped
    preferences.letterSpacing = clamped
    rootView.updateLetterSpacing(clamped)
    if document != nil {
      rebuildPagination(preserving: anchor)
    }
  }

  private var currentAnchor: Int {
    if let pendingAnchor { return pendingAnchor }
    guard pages.indices.contains(currentPageIndex) else { return 0 }
    return pages[currentPageIndex].location
  }

  private func rebuildPagination(preserving anchor: Int) {
    guard let document else { return }
    let pageSize = rootView.canvas.pageSize(for: pageMode)
    guard pageSize.width >= 16, pageSize.height >= 16 else { return }

    paginationCancellation?.cancel()
    let cancellation = PaginationCancellation()
    paginationCancellation = cancellation
    paginationGeneration += 1
    let generation = paginationGeneration
    let configuration = TextLayoutConfiguration(
      pageWidth: pageSize.width,
      pageHeight: pageSize.height,
      fontSize: fontSize,
      letterSpacing: letterSpacing
    )

    pendingAnchor = min(max(0, anchor), (document.text as NSString).length)
    pendingSeekProgress = nil
    paginationComplete = false
    isAwaitingPaginationLayout = true
    rootView.setProgressSeekingEnabled(false)
    rootView.disablePageNavigation()
    rootView.setLoading(true)

    paginationQueue.async { [weak self] in
      PaginationEngine.paginate(
        text: document.text,
        configuration: configuration,
        cancellation: cancellation
      ) { layout, batch, complete in
        DispatchQueue.main.async {
          self?.receive(
            layout: layout,
            batch: batch,
            complete: complete,
            generation: generation
          )
        }
      }
    }
  }

  private func receive(
    layout: TextLayout,
    batch: [PageRange],
    complete: Bool,
    generation: Int
  ) {
    guard generation == paginationGeneration else { return }

    if self.layout !== layout {
      self.layout = layout
      pages.removeAll(keepingCapacity: true)
      currentPageIndex = 0
      isAwaitingPaginationLayout = false
    }
    pages.append(contentsOf: batch)
    paginationComplete = complete

    let canResolvePendingAnchor =
      pendingAnchor.map { anchor in
        complete || anchor < (pages.last?.upperBound ?? 0)
      } ?? false
    var didResolvePendingAnchor = false
    if canResolvePendingAnchor,
      let anchor = pendingAnchor,
      let target = PaginationEngine.pageIndex(containing: anchor, in: pages)
    {
      currentPageIndex = alignedPageIndex(target)
      pendingAnchor = nil
      pendingSeekProgress = nil
      didResolvePendingAnchor = true
    }

    applyVisiblePages(persistPosition: didResolvePendingAnchor)
    if let pendingSeekProgress {
      rootView.previewProgress(percent: pendingSeekProgress)
    }
    if complete {
      pendingAnchor = nil
      rootView.setLoading(false)
    }
  }

  private func navigate(by delta: Int) {
    guard !isAwaitingPaginationLayout, !pages.isEmpty else { return }
    let destination = currentPageIndex + delta
    guard destination >= 0, destination < pages.count else { return }
    pendingAnchor = paginationComplete ? nil : pages[destination].location
    pendingSeekProgress = nil
    currentPageIndex = destination
    applyVisiblePages(persistPosition: true)
  }

  private func applyVisiblePages(persistPosition: Bool) {
    guard let layout, !pages.isEmpty else {
      rootView.updateProgress(percent: 0, canGoPrevious: false, canGoNext: false)
      rootView.setProgressSeekingEnabled(false)
      return
    }

    currentPageIndex = alignedPageIndex(currentPageIndex)
    let visiblePages = (0..<pageMode.pageAdvance).compactMap { offset -> PageRange? in
      let index = currentPageIndex + offset
      return pages.indices.contains(index) ? pages[index] : nil
    }
    rootView.canvas.show(layout: layout, pages: visiblePages, mode: pageMode)

    let visibleLastIndex = min(pages.count - 1, currentPageIndex + pageMode.pageAdvance - 1)
    let textLength = max(0, layout.textLength)
    let progress: Double
    if textLength == 0 {
      progress = 0
    } else {
      progress = min(1, Double(pages[visibleLastIndex].upperBound) / Double(textLength))
    }

    let canGoNext =
      currentPageIndex + pageMode.pageAdvance < pages.count
      || !paginationComplete
    rootView.updateProgress(
      percent: progress,
      canGoPrevious: currentPageIndex > 0,
      canGoNext: canGoNext
    )
    rootView.setProgressSeekingEnabled(textLength > 0)
    if persistPosition {
      persistReadingPosition()
    }
  }

  private func alignedPageIndex(_ index: Int) -> Int {
    guard !pages.isEmpty else { return 0 }
    let clamped = max(0, min(index, pages.count - 1))
    guard pageMode == .spread else { return clamped }
    return clamped - clamped % pageMode.pageAdvance
  }

  private func seek(toProgress progress: Double, finished: Bool) {
    guard !isAwaitingPaginationLayout,
      let layout,
      !pages.isEmpty,
      layout.textLength > 0
    else { return }
    let clampedProgress = min(max(progress, 0), 1)
    let anchor = PaginationEngine.anchor(
      forProgress: clampedProgress,
      textLength: layout.textLength
    )
    let canResolveAnchor =
      paginationComplete || anchor < (pages.last?.upperBound ?? 0)

    if canResolveAnchor,
      let target = PaginationEngine.pageIndex(containing: anchor, in: pages)
    {
      pendingAnchor = nil
      pendingSeekProgress = nil
      let destination = alignedPageIndex(target)
      if destination != currentPageIndex || finished {
        currentPageIndex = destination
        applyVisiblePages(persistPosition: finished)
      }
      if !finished {
        rootView.previewProgress(percent: clampedProgress)
      }
      return
    }

    pendingAnchor = anchor
    pendingSeekProgress = clampedProgress
    rootView.previewProgress(percent: clampedProgress)
    if finished {
      persistReadingPosition()
    }
  }

  private func scheduleResizeReflow() {
    guard let document else { return }
    resizeWorkItem?.cancel()
    let documentIdentity = document.persistenceIdentity
    let workItem = DispatchWorkItem { [weak self] in
      guard let self,
        self.document?.persistenceIdentity == documentIdentity
      else { return }
      self.resizeWorkItem = nil
      self.rebuildPagination(preserving: self.currentAnchor)
    }
    resizeWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: workItem)
  }

  private func cancelScheduledResizeReflow() {
    resizeWorkItem?.cancel()
    resizeWorkItem = nil
  }

  private func installEventMonitorIfNeeded() {
    guard eventMonitor == nil else { return }
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, event.window === self.view.window else { return event }
      if event.window?.firstResponder === self.rootView.progressIndicator {
        return event
      }
      let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      if modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option)
      {
        return event
      }

      switch event.keyCode {
      case 123, 116:  // left, page up
        self.goToPreviousPage()
        return nil
      case 124, 121:  // right, page down
        self.goToNextPage()
        return nil
      case 49:  // space
        if let firstResponder = self.view.window?.firstResponder,
          firstResponder !== self.rootView.canvas
        {
          return event
        }
        modifiers.contains(.shift) ? self.goToPreviousPage() : self.goToNextPage()
        return nil
      case 115:  // home
        self.goToBeginning()
        return nil
      case 119:  // end
        self.goToEnd()
        return nil
      default:
        return event
      }
    }
  }

  private func present(error: Error) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "파일을 열지 못했습니다"
    alert.informativeText =
      (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    alert.addButton(withTitle: "확인")
    if let window = view.window {
      alert.beginSheetModal(for: window)
    } else {
      alert.runModal()
    }
  }

  @objc private func openButtonPressed() { openPanel() }
  @objc private func singlePagePressed() { showSinglePage() }
  @objc private func spreadPressed() { showSpread() }
  @objc private func increaseFontPressed() { increaseFontSize() }
  @objc private func decreaseFontPressed() { decreaseFontSize() }
  @objc private func increaseLetterSpacingPressed() { increaseLetterSpacing() }
  @objc private func decreaseLetterSpacingPressed() { decreaseLetterSpacing() }
  @objc private func previousPressed() { goToPreviousPage() }
  @objc private func nextPressed() { goToNextPage() }
}
