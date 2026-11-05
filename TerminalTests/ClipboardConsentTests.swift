import XCTest
import UIKit
@testable import Terminal

final class ClipboardConsentTests: XCTestCase {
    @MainActor
    private func connection(_ profile: ServerProfile) -> SSHConnection {
        SSHConnection(profile: profile, authMethodFor: { _ in throw CancellationError() },
                      validatorFor: { profile, _ in
                          HostKeyTrustValidator(host: profile.host, port: profile.port, knownKey: nil) { _ in false }
                      }, bastionResolver: { _ in throw CancellationError() }, onStateChange: { _ in })
    }

    @MainActor
    private func withSession(_ body: (TerminalSession, SettingsStore, ServerProfile) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = SettingsStore(directory: directory)
        settings.settings.remoteClipboard = true
        var profile = ServerProfile()
        profile.host = "first.example.test"
        let session = TerminalSession(profile: profile, connection: connection(profile), settings: settings)
        let previous = UIPasteboard.general.items
        defer { session.terminate(); UIPasteboard.general.items = previous }
        try body(session, settings, profile)
    }

    @MainActor
    func testRetargetRevokesConsentAndRejectsOldDialogAnswer() throws {
        try withSession { session, _, profile in
            let oldConsentID = session.clipboardConsentID
            session.approveClipboardWrite(Data("approved peer".utf8), consentID: oldConsentID)
            XCTAssertTrue(session.clipboardAllowed)
            var changed = profile
            changed.host = "second.example.test"
            session.retarget(profile: changed, connection: connection(changed))
            XCTAssertFalse(session.clipboardAllowed)
            XCTAssertNotEqual(session.clipboardConsentID, oldConsentID)
            UIPasteboard.general.string = "untouched"
            session.approveClipboardWrite(Data("stale approval".utf8), consentID: oldConsentID)
            session.clipboardWrite(Data("new peer without consent".utf8))
            XCTAssertFalse(session.clipboardAllowed)
            XCTAssertEqual(UIPasteboard.general.string, "untouched")
            session.approveClipboardWrite(Data("new explicit approval".utf8), consentID: session.clipboardConsentID)
            XCTAssertEqual(UIPasteboard.general.string, "new explicit approval")
        }
    }

    @MainActor
    func testMetadataEditOnSameConnectionPreservesCurrentPeerConsent() throws {
        try withSession { session, _, profile in
            let consentID = session.clipboardConsentID
            session.approveClipboardWrite(Data("initial".utf8), consentID: consentID)
            var renamed = profile
            renamed.name = "Renamed server"
            session.retarget(profile: renamed, connection: session.connection)
            XCTAssertEqual(session.clipboardConsentID, consentID)
            XCTAssertTrue(session.clipboardAllowed)
            session.clipboardWrite(Data("same peer".utf8))
            XCTAssertEqual(UIPasteboard.general.string, "same peer")
        }
    }

    @MainActor
    func testReconnectRevokesConsentEvenAtTheSameEndpoint() throws {
        try withSession { session, _, _ in
            let oldConsentID = session.clipboardConsentID
            session.approveClipboardWrite(Data("initial".utf8), consentID: oldConsentID)
            session.reconnect()
            XCTAssertFalse(session.clipboardAllowed)
            XCTAssertNotEqual(session.clipboardConsentID, oldConsentID)
            UIPasteboard.general.string = "untouched"
            session.approveClipboardWrite(Data("late approval".utf8), consentID: oldConsentID)
            XCTAssertEqual(UIPasteboard.general.string, "untouched")
        }
    }

    @MainActor
    func testClosedSessionCannotWriteOrAcceptPendingApproval() throws {
        try withSession { session, _, _ in
            let consentID = session.clipboardConsentID
            session.terminate()
            UIPasteboard.general.string = "untouched"
            session.approveClipboardWrite(Data("late reply".utf8), consentID: consentID)
            session.clipboardWrite(Data("late output".utf8))
            XCTAssertFalse(session.clipboardAllowed)
            XCTAssertEqual(UIPasteboard.general.string, "untouched")
        }
    }

    @MainActor
    func testDisabledSettingAndOversizedRequestsCannotGrantConsent() throws {
        try withSession { session, settings, _ in
            UIPasteboard.general.string = "untouched"
            settings.settings.remoteClipboard = false
            session.approveClipboardWrite(Data("disabled".utf8), consentID: session.clipboardConsentID)
            XCTAssertFalse(session.clipboardAllowed)
            settings.settings.remoteClipboard = true
            session.approveClipboardWrite(Data(repeating: 65, count: 512_001), consentID: session.clipboardConsentID)
            XCTAssertFalse(session.clipboardAllowed)
            XCTAssertEqual(UIPasteboard.general.string, "untouched")
        }
    }
}
