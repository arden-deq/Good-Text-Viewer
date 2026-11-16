import Foundation
import XCTest

@testable import GoodTextViewer

final class ReaderViewControllerStateTests: XCTestCase {
  func testRepairReloadPrefersNewestRequestedDocument() {
    let installed = URL(fileURLWithPath: "/tmp/A.txt")
    let requested = URL(fileURLWithPath: "/tmp/B.txt")

    XCTAssertEqual(
      ReaderViewController.preferredRepairReloadURL(
        requestedURL: requested,
        documentURL: installed
      ),
      requested
    )
  }

  func testRepairReloadDoesNotMapInstalledDocumentProgressOntoDifferentRequest() {
    let installed = URL(fileURLWithPath: "/tmp/A.txt")
    let requested = URL(fileURLWithPath: "/tmp/B.txt")

    XCTAssertNil(
      ReaderViewController.repairReloadProgress(
        documentURL: installed,
        reloadURL: requested,
        anchor: 500,
        textLength: 1_000
      )
    )
  }

  func testRepairReloadMapsProgressForSameDocument() {
    let document = URL(fileURLWithPath: "/tmp/../tmp/A.txt")

    XCTAssertEqual(
      ReaderViewController.repairReloadProgress(
        documentURL: document,
        reloadURL: URL(fileURLWithPath: "/tmp/A.txt"),
        anchor: 250,
        textLength: 1_000
      ),
      0.25
    )
  }
}
