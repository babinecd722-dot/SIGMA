import XCTest
import UIKit
@testable import SwiftTerm
@testable import Terminal

final class TerminalSelectionTests: XCTestCase {
    @MainActor
    func testHoldSelectsAndCopiesWordWithMouseReportingEnabled() async throws {
        try await assertWordCopy(text: "hello world", expected: "hello", mouse: true)
    }

    @MainActor
    func testLocalCopyPreservesUnicode() async throws {
        try await assertWordCopy(text: "привет мир", expected: "привет", mouse: false)
    }

    @MainActor
    private func assertWordCopy(text: String, expected: String, mouse: Bool) async throws {
        let previousClipboard = UIPasteboard.general.items
        defer { UIPasteboard.general.items = previousClipboard }
        let view = AccessibleTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 200))
        TerminalSurface.applyStyle(view, fontSize: 16, theme: .paper)
        if mouse { view.feed(text: "\u{1b}[?1000h\u{1b}[?1006h") }
        view.feed(text: text)
        try await Task.sleep(for: .milliseconds(100))
        view.selectWordForCopy(at: CGPoint(x: 8, y: 8))
        XCTAssertFalse(view.isFirstResponder, "Selecting output must not open or resize the keyboard")
        XCTAssertTrue(view.hasActiveSelection)
        XCTAssertTrue(view.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil))
        view.copy(nil)
        XCTAssertEqual(UIPasteboard.general.string, expected)
        XCTAssertFalse(view.hasActiveSelection)
    }

    @MainActor
    func testCopyUsesTheTouchedScrollbackRow() async throws {
        let previousClipboard = UIPasteboard.general.items
        defer { UIPasteboard.general.items = previousClipboard }
        let view = AccessibleTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 140))
        TerminalSurface.applyStyle(view, fontSize: 13, theme: .paper)
        view.feed(text: (0..<45).map { "word\($0)\r\n" }.joined())
        try await Task.sleep(for: .milliseconds(150))
        let height = view.cellDimension.height
        view.contentSize = CGSize(width: 390, height: 45 * height)
        view.contentOffset.y = 7 * height
        view.selectWordForCopy(at: CGPoint(x: 8, y: view.bounds.minY + height / 2))
        view.copy(nil)
        XCTAssertEqual(UIPasteboard.general.string, "word7")
    }
}
