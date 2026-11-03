import XCTest
import UIKit
import SwiftTerm
@testable import Terminal

final class TerminalAppearanceTests: XCTestCase {
    @MainActor
    func testLightDarkSwitchRepaintsExistingTerminalAndSurvivesResize() async throws {
        let view = AccessibleTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let host = UIViewController()
        host.view.addSubview(view)
        let window = UIWindow(frame: view.frame)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        view.feed(text: "Visible text\r\n\u{1b}[31mRed\u{1b}[0m\r\n")

        for theme in [TerminalTheme.paper, .pro, .paper, .graphite, .paper] {
            TerminalSurface.applyStyle(view, fontSize: 14, theme: theme)
            view.frame.size = CGSize(width: theme.id == "paper" ? 600 : 390, height: 400)
            view.setNeedsLayout()
            view.layoutIfNeeded()
            // Drain the library's queued color callbacks and display frames.
            try await Task.sleep(for: .milliseconds(100))
            assertColor(view.nativeBackgroundColor, equals: theme.uiBackground)
            assertColor(view.nativeForegroundColor, equals: theme.uiForeground)
            assertColor(UIColor(cgColor: try XCTUnwrap(view.layer.backgroundColor)), equals: theme.uiBackground)
            XCTAssertEqual(view.keyboardAppearance, theme.id == "paper" ? .light : .dark)
            XCTAssertTrue(view.accessibilityValue?.contains("Visible text") == true)
            XCTAssertTrue(view.accessibilityValue?.contains("Red") == true)
        }
    }

    @MainActor
    func testThemeChangePreservesGrid() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        TerminalSurface.applyStyle(view, fontSize: 14, theme: .pro)
        let dimensions = view.terminalDimensions
        TerminalSurface.applyStyle(view, fontSize: 14, theme: .paper)
        XCTAssertEqual(view.terminalDimensions.cols, dimensions.cols)
        XCTAssertEqual(view.terminalDimensions.rows, dimensions.rows)
    }

    @MainActor
    private func assertColor(_ actual: UIColor, equals expected: UIColor, file: StaticString = #filePath, line: UInt = #line) {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var er: CGFloat = 0, eg: CGFloat = 0, eb: CGFloat = 0, ea: CGFloat = 0
        actual.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        expected.getRed(&er, green: &eg, blue: &eb, alpha: &ea)
        XCTAssertEqual(ar, er, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(ag, eg, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(ab, eb, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(aa, ea, accuracy: 0.01, file: file, line: line)
    }
}
