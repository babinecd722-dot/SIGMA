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
        await waitForText(text, in: view)
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
        await waitForText("word44", in: view)
        let height = view.cellDimension.height
        view.contentSize = CGSize(width: 390, height: 45 * height)
        view.contentOffset.y = 7 * height
        view.selectWordForCopy(at: CGPoint(x: 8, y: view.bounds.minY + height / 2))
        view.copy(nil)
        XCTAssertEqual(UIPasteboard.general.string, "word7")
    }

    @MainActor
    func testHoldOnAnEmptyRowDoesNotSelectTheWholeRow() async {
        let view = await fixture("hello world")
        let hold = CopyHold()
        hold.point = CGPoint(x: 100, y: 5.5 * view.cellDimension.height)
        hold.state = .began
        view.longPress(hold)
        hold.state = .ended
        view.longPress(hold)
        XCTAssertFalse(view.hasActiveSelection)
        XCTAssertFalse(view.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil))
        XCTAssertEqual(menuActionIDs(in: view), ["terminal.paste"])
    }

    @MainActor
    func testHoldOnSpacesAndUnusedColumnsDoesNotSelectWhitespace() async {
        let view = await fixture("hello   world")
        for column in [6, 24] {
            view.selectWordForCopy(at: CGPoint(x: (CGFloat(column) + 0.5) * view.cellDimension.width, y: 8))
            XCTAssertFalse(view.hasActiveSelection, "Column \(column) contains only space or an unused cell")
        }
    }

    @MainActor
    func testHoldingAndDraggingForwardKeepsTheSeedWord() async {
        let view = await fixture("hello world")
        let hold = CopyHold()
        hold.point = CGPoint(x: view.cellDimension.width, y: 8)
        hold.state = .began
        view.longPress(hold)
        XCTAssertEqual(selectedText(in: view), "hello")
        hold.point.x = 8 * view.cellDimension.width
        hold.state = .changed
        view.longPress(hold)
        hold.state = .ended
        view.longPress(hold)
        assertCopiedText("hello world", from: view)
        XCTAssertFalse(view.isFirstResponder)
    }

    @MainActor
    func testHoldingAndDraggingBackwardKeepsTheSeedWord() async {
        let view = await fixture("hello world")
        let hold = CopyHold()
        hold.point = CGPoint(x: 8 * view.cellDimension.width, y: 8)
        hold.state = .began
        view.longPress(hold)
        XCTAssertEqual(selectedText(in: view), "world")
        hold.point.x = view.cellDimension.width
        hold.state = .changed
        view.longPress(hold)
        hold.state = .ended
        view.longPress(hold)
        assertCopiedText("hello world", from: view)
    }

    @MainActor
    func testHeldDragIntoTrailingBlankCellsStopsAtTheFinger() async {
        let view = await fixture("hello")
        let hold = CopyHold()
        hold.point = CGPoint(x: view.cellDimension.width, y: 8)
        hold.state = .began
        view.longPress(hold)
        hold.point.x = 8.5 * view.cellDimension.width
        hold.state = .changed
        view.longPress(hold)
        view.withTerminal { _ in
            XCTAssertEqual(view.selection.start.col, 0)
            XCTAssertEqual(view.selection.end.col, 8,
                           "Dragging into trailing space must not select every unused column")
        }
        hold.state = .ended
        view.longPress(hold)
        XCTAssertTrue(selectedText(in: view).hasPrefix("hello"))
    }

    @MainActor
    func testHandleDragPreservesTouchOffsetInsteadOfJumpingOnTouchDown() async {
        let view = await fixture("hello world")
        view.selectWordForCopy(at: CGPoint(x: 8, y: 8))
        let pan = CopyPan()
        pan.point = CGPoint(x: 5 * view.cellDimension.width + 10, y: view.cellDimension.height + 12)
        XCTAssertEqual(view.copySelectionHandle(at: pan.point), false)
        pan.state = .began
        view.panSelectionHandler(pan)
        XCTAssertEqual(selectedText(in: view), "hello", "Grabbing the visible knob must not jump to the finger's grid cell")
        pan.point.x += 6 * view.cellDimension.width
        pan.state = .changed
        view.panSelectionHandler(pan)
        pan.state = .ended
        view.panSelectionHandler(pan)
        assertCopiedText("hello world", from: view)
    }

    @MainActor
    func testSwipeAwayFromHandlesCannotStretchTheSelection() async {
        let view = await fixture("hello world")
        view.selectWordForCopy(at: CGPoint(x: 8, y: 8))
        let pan = CopyPan()
        pan.point = CGPoint(x: 300, y: 150)
        XCTAssertNil(view.copySelectionHandle(at: pan.point))
        let installed = view.panSelectionGesture
        XCTAssertNotNil(installed?.delegate)
        XCTAssertEqual(installed?.delegate?.gestureRecognizerShouldBegin?(pan), false)
        pan.state = .began
        view.panSelectionHandler(pan)
        pan.point = CGPoint(x: 330, y: 175)
        pan.state = .changed
        view.panSelectionHandler(pan)
        pan.state = .ended
        view.panSelectionHandler(pan)
        assertCopiedText("hello", from: view)
    }

    @MainActor
    func testSelectionMenuDoesNotIncludeSuggestedCredentialOrRewritingActions() async {
        let view = await fixture("hello world")
        view.selectWordForCopy(at: CGPoint(x: 8, y: 8))
        XCTAssertEqual(menuActionIDs(in: view), ["terminal.copy", "terminal.selectAll"])
        XCTAssertFalse(view.isFirstResponder)
        XCTAssertTrue(view.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil))
        XCTAssertTrue(view.canPerformAction(#selector(UIResponderStandardEditActions.paste(_:)), withSender: nil))
        XCTAssertFalse(view.canPerformAction(#selector(UIResponderStandardEditActions.cut(_:)), withSender: nil))
        XCTAssertNil(view.textContentType)
        XCTAssertFalse(view.isSecureTextEntry, "Terminal input must retain its ordinary keyboard and composition behavior")
        view.clearSelection()
        XCTAssertEqual(menuActionIDs(in: view), ["terminal.paste"])
    }

    @MainActor
    func testHoldingTheTrailingCellOfAWideGlyphCopiesTheGlyph() async {
        let view = await fixture("界 abc")
        view.selectWordForCopy(at: CGPoint(x: 1.5 * view.cellDimension.width, y: 8))
        assertCopiedText("界", from: view)
    }

    @MainActor
    private func fixture(_ text: String) async -> AccessibleTerminalView {
        let view = AccessibleTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 200))
        TerminalSurface.applyStyle(view, fontSize: 16, theme: .paper)
        view.feed(text: text)
        await waitForText(text, in: view)
        return view
    }

    @MainActor
    private func waitForText(_ text: String, in view: AccessibleTerminalView) async {
        let rendered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            view.accessibilityValue?.contains(text) == true
        }, object: view)
        await fulfillment(of: [rendered], timeout: 3)
    }

    @MainActor
    private func selectedText(in view: AccessibleTerminalView) -> String {
        view.withTerminal { _ in view.selection.getSelectedText() }
    }

    @MainActor
    private func assertCopiedText(_ expected: String, from view: AccessibleTerminalView,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let previous = UIPasteboard.general.items
        defer { UIPasteboard.general.items = previous }
        view.copy(nil)
        XCTAssertEqual(UIPasteboard.general.string, expected, file: file, line: line)
    }

    @MainActor
    private func menuActionIDs(in view: AccessibleTerminalView) -> [String] {
        // Deliberately offer actions a password provider / system rewriting
        // service could suggest. Only terminal-owned actions may survive.
        let suggestions: [UIMenuElement] = [
            UIAction(title: "Insert Passkey", identifier: UIAction.Identifier("test.credentials")) { _ in },
            UIMenu(title: "Writing Tools", children: [UIAction(title: "Rewrite") { _ in }])
        ]
        let interaction = UIEditMenuInteraction(delegate: view)
        let menu = view.editMenuInteraction(interaction,
            menuFor: UIEditMenuConfiguration(identifier: nil, sourcePoint: .zero), suggestedActions: suggestions)
        return menu?.children.compactMap { ($0 as? UIAction)?.identifier.rawValue } ?? []
    }

    @MainActor
    private final class CopyHold: UILongPressGestureRecognizer {
        var point = CGPoint.zero
        var testState: UIGestureRecognizer.State = .possible
        override var state: UIGestureRecognizer.State {
            get { testState }
            set { testState = newValue }
        }
        override func location(in view: UIView?) -> CGPoint { point }
    }

    @MainActor
    private final class CopyPan: UIPanGestureRecognizer {
        var point = CGPoint.zero
        var testState: UIGestureRecognizer.State = .possible
        override var state: UIGestureRecognizer.State {
            get { testState }
            set { testState = newValue }
        }
        override func location(in view: UIView?) -> CGPoint { point }
    }
}
