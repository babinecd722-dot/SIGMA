import XCTest
import UIKit
import NIO
@testable import SwiftTerm
@testable import Citadel
@testable import Terminal

final class TerminalRecoveryTests: XCTestCase {
    @MainActor
    func testMissingExitStatusNeverClosesTheTabAsLogout() {
        XCTAssertFalse(TerminalSession.endedByRemoteShell(SSHClient.PTYClosedWithoutExit()))
        XCTAssertFalse(TerminalSession.endedByRemoteShell(ChannelError.alreadyClosed))
        XCTAssertFalse(TerminalSession.endedByRemoteShell(nil))
        XCTAssertTrue(TerminalSession.endedByRemoteShell(nil, processExited: true))
        XCTAssertTrue(TerminalSession.endedByRemoteShell(SSHClient.CommandFailed(exitCode: 1)))
    }

    @MainActor
    func testNewPTYClearsOldScreenAndPreservesReadablePalette() async throws {
        for theme in [TerminalTheme.paper, .pro, .graphite, .homebrew] {
            let view = AccessibleTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 240))
            TerminalSurface.applyStyle(view, fontSize: 13, theme: theme)
            view.feed(text: "OLD_SESSION")
            try await Task.sleep(for: .milliseconds(100))
            view.selectWordForCopy(at: CGPoint(x: 8, y: 8))
            XCTAssertTrue(view.hasActiveSelection)
            view.feed(text: "\u{1b}[?1h\u{1b}[?1049h\u{1b}[?1000h\u{1b}[?25l")
            view.feed(text: String(decoding: TerminalSession.freshPTYReset, as: UTF8.self) + "AFTER_RESTART")
            try await Task.sleep(for: .milliseconds(100))
            let text = view.visibleRowsText(0..<view.terminalDimensions.rows).joined()
            XCTAssertTrue(text.contains("AFTER_RESTART"), text)
            XCTAssertFalse(text.contains("OLD_SESSION"), text)
            XCTAssertFalse(view.terminalInputStateSnapshot()?.applicationCursor ?? true)
            XCTAssertFalse(view.hasActiveSelection)
            XCTAssertFalse(view.withTerminal { $0.cursorHidden })
            for (actual, expected) in [(view.nativeBackgroundColor, theme.uiBackground),
                                       (view.nativeForegroundColor, theme.uiForeground)] {
                var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
                var er: CGFloat = 0, eg: CGFloat = 0, eb: CGFloat = 0, ea: CGFloat = 0
                actual.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
                expected.getRed(&er, green: &eg, blue: &eb, alpha: &ea)
                XCTAssertEqual(ar, er, accuracy: 0.01)
                XCTAssertEqual(ag, eg, accuracy: 0.01)
                XCTAssertEqual(ab, eb, accuracy: 0.01)
                XCTAssertEqual(aa, ea, accuracy: 0.01)
            }
        }
    }
}
