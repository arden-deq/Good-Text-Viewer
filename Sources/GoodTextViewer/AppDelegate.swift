import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var windowController: ReaderWindowController?
  private var pendingURLs: [URL] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    buildMainMenu()
    let controller = ReaderWindowController()
    windowController = controller
    controller.showWindow(nil)
    controller.window?.center()
    NSApp.activate(ignoringOtherApps: true)

    if let pending = pendingURLs.first {
      pendingURLs.removeAll()
      controller.readerViewController.open(url: pending)
    } else {
      controller.readerViewController.restoreLastDocumentIfAvailable()
    }
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    guard let url = urls.first else { return }
    if let windowController {
      windowController.readerViewController.open(url: url)
      windowController.showWindow(nil)
    } else {
      pendingURLs = [url]
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    true
  }

  func applicationWillTerminate(_ notification: Notification) {
    windowController?.readerViewController.persistReadingPosition()
  }

  @objc private func openDocument(_ sender: Any?) {
    windowController?.readerViewController.openPanel()
  }

  @objc private func singlePage(_ sender: Any?) {
    windowController?.readerViewController.showSinglePage()
  }

  @objc private func spread(_ sender: Any?) {
    windowController?.readerViewController.showSpread()
  }

  @objc private func increaseFont(_ sender: Any?) {
    windowController?.readerViewController.increaseFontSize()
  }

  @objc private func decreaseFont(_ sender: Any?) {
    windowController?.readerViewController.decreaseFontSize()
  }

  @objc private func increaseLetterSpacing(_ sender: Any?) {
    windowController?.readerViewController.increaseLetterSpacing()
  }

  @objc private func decreaseLetterSpacing(_ sender: Any?) {
    windowController?.readerViewController.decreaseLetterSpacing()
  }

  @objc private func toggleLegacyHardWrapRepair(_ sender: Any?) {
    guard let reader = windowController?.readerViewController else { return }
    let enabled = reader.toggleLegacyHardWrapRepair()
    (sender as? NSMenuItem)?.state = enabled ? .on : .off
  }

  @objc private func previousPage(_ sender: Any?) {
    windowController?.readerViewController.goToPreviousPage()
  }

  @objc private func nextPage(_ sender: Any?) {
    windowController?.readerViewController.goToNextPage()
  }

  private func buildMainMenu() {
    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu()
    appMenu.addItem(
      withTitle: "Good Text Viewer 정보",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "Good Text Viewer 숨기기", action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h")
    appMenu.addItem(
      withTitle: "기타 숨기기", action: #selector(NSApplication.hideOtherApplications(_:)),
      keyEquivalent: "h"
    ).keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(
      withTitle: "모두 보기", action: #selector(NSApplication.unhideAllApplications(_:)),
      keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "Good Text Viewer 종료", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    appMenuItem.submenu = appMenu

    let fileMenuItem = NSMenuItem()
    mainMenu.addItem(fileMenuItem)
    let fileMenu = NSMenu(title: "파일")
    fileMenu.addItem(withTitle: "열기…", action: #selector(openDocument(_:)), keyEquivalent: "o")
      .target = self
    fileMenu.addItem(.separator())
    fileMenu.addItem(
      withTitle: "창 닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    fileMenuItem.submenu = fileMenu

    let viewMenuItem = NSMenuItem()
    mainMenu.addItem(viewMenuItem)
    let viewMenu = NSMenu(title: "보기")
    let single = viewMenu.addItem(
      withTitle: "한쪽 보기", action: #selector(singlePage(_:)), keyEquivalent: "1")
    single.target = self
    let two = viewMenu.addItem(
      withTitle: "두쪽 보기", action: #selector(spread(_:)), keyEquivalent: "2")
    two.target = self
    viewMenu.addItem(.separator())
    let larger = viewMenu.addItem(
      withTitle: "글자 크게", action: #selector(increaseFont(_:)), keyEquivalent: "+")
    larger.target = self
    let smaller = viewMenu.addItem(
      withTitle: "글자 작게", action: #selector(decreaseFont(_:)), keyEquivalent: "-")
    smaller.target = self
    viewMenu.addItem(.separator())
    let wider = viewMenu.addItem(
      withTitle: "자간 넓게",
      action: #selector(increaseLetterSpacing(_:)),
      keyEquivalent: "]"
    )
    wider.keyEquivalentModifierMask = [.command, .option]
    wider.target = self
    let narrower = viewMenu.addItem(
      withTitle: "자간 좁게",
      action: #selector(decreaseLetterSpacing(_:)),
      keyEquivalent: "["
    )
    narrower.keyEquivalentModifierMask = [.command, .option]
    narrower.target = self
    viewMenu.addItem(.separator())
    let hardWrapRepair = viewMenu.addItem(
      withTitle: "오래된 문서 줄바꿈 자동 정리",
      action: #selector(toggleLegacyHardWrapRepair(_:)),
      keyEquivalent: ""
    )
    hardWrapRepair.target = self
    hardWrapRepair.state = ReaderPreferences.shared.repairsLegacyHardWraps ? .on : .off
    viewMenuItem.submenu = viewMenu

    let navigationMenuItem = NSMenuItem()
    mainMenu.addItem(navigationMenuItem)
    let navigationMenu = NSMenu(title: "이동")
    let previous = navigationMenu.addItem(
      withTitle: "이전 페이지", action: #selector(previousPage(_:)), keyEquivalent: "")
    previous.target = self
    let next = navigationMenu.addItem(
      withTitle: "다음 페이지", action: #selector(nextPage(_:)), keyEquivalent: "")
    next.target = self
    navigationMenuItem.submenu = navigationMenu

    let windowMenuItem = NSMenuItem()
    mainMenu.addItem(windowMenuItem)
    let windowMenu = NSMenu(title: "윈도우")
    windowMenu.addItem(
      withTitle: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    windowMenu.addItem(
      withTitle: "확대/축소", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
    windowMenuItem.submenu = windowMenu
    NSApp.windowsMenu = windowMenu

    NSApp.mainMenu = mainMenu
  }
}
