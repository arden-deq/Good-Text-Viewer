import AppKit

final class ReaderWindowController: NSWindowController, NSWindowDelegate {
  let readerViewController = ReaderViewController()

  init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = "Good Text Viewer"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = false
    window.minSize = NSSize(width: 760, height: 560)
    window.backgroundColor = NSColor(
      calibratedRed: 226.0 / 255.0,
      green: 204.0 / 255.0,
      blue: 161.0 / 255.0,
      alpha: 1
    )
    window.contentViewController = readerViewController
    window.setFrameAutosaveName("GoodTextViewerMainWindow")

    super.init(window: window)
    window.delegate = self
    shouldCascadeWindows = true
  }

  required init?(coder: NSCoder) {
    nil
  }

  func windowWillClose(_ notification: Notification) {
    readerViewController.persistReadingPosition()
  }
}
