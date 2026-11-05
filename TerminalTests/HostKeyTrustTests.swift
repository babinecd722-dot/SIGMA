import XCTest
import CryptoKit
import NIO
import NIOSSH
@testable import Terminal

final class HostKeyTrustTests: XCTestCase {
    private actor Decisions {
        private(set) var events: [HostKeyEvent] = []
        func record(_ event: HostKeyEvent, accepting: Bool) -> Bool {
            events.append(event)
            return accepting
        }
    }

    private func publicKey(_ byte: UInt8) throws -> NIOSSHPublicKey {
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: byte, count: 32))
        return NIOSSHPrivateKey(ed25519Key: privateKey).publicKey
    }

    private func validate(_ key: NIOSSHPublicKey, known: String?, accepting: Bool,
                          decisions: Decisions) async throws -> Bool {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let promise = group.next().makePromise(of: Void.self)
        let validator = HostKeyTrustValidator(host: "example.test", port: 2222, knownKey: known) { event in
            await decisions.record(event, accepting: accepting)
        }
        validator.validateHostKey(hostKey: key, validationCompletePromise: promise)
        let accepted: Bool
        do {
            try await promise.futureResult.get()
            accepted = true
        } catch {
            XCTAssertTrue(error is UntrustedHostKey)
            accepted = false
        }
        try await group.shutdownGracefully()
        return accepted
    }

    func testMatchingKnownKeyDoesNotPrompt() async throws {
        let key = try publicKey(1)
        let decisions = Decisions()
        let accepted = try await validate(key, known: String(openSSHPublicKey: key), accepting: false, decisions: decisions)
        let events = await decisions.events
        XCTAssertTrue(accepted)
        XCTAssertTrue(events.isEmpty)
    }

    func testUnknownKeyRequiresExplicitDecision() async throws {
        let key = try publicKey(1)
        let line = String(openSSHPublicKey: key)
        for accepting in [false, true] {
            let decisions = Decisions()
            let accepted = try await validate(key, known: nil, accepting: accepting, decisions: decisions)
            let events = await decisions.events
            XCTAssertEqual(accepted, accepting)
            XCTAssertEqual(events, [.unknown(host: "example.test", port: 2222, keyLine: line,
                                             fingerprint: HostKeyTrustValidator.fingerprint(of: line))])
        }
    }

    func testChangedKeyCannotReuseExistingTrust() async throws {
        let known = String(openSSHPublicKey: try publicKey(1))
        let key = try publicKey(2)
        let line = String(openSSHPublicKey: key)
        XCTAssertNotEqual(known, line)
        for accepting in [false, true] {
            let decisions = Decisions()
            let accepted = try await validate(key, known: known, accepting: accepting, decisions: decisions)
            let events = await decisions.events
            XCTAssertEqual(accepted, accepting)
            XCTAssertEqual(events, [.changed(host: "example.test", port: 2222, keyLine: line,
                                             expectedFingerprint: HostKeyTrustValidator.fingerprint(of: known),
                                             fingerprint: HostKeyTrustValidator.fingerprint(of: line))])
        }
    }

    func testMalformedStoredKeyIsNeverTreatedAsUnknownOrMatching() async throws {
        let decisions = Decisions()
        let accepted = try await validate(publicKey(1), known: "damaged key", accepting: false, decisions: decisions)
        let events = await decisions.events
        XCTAssertFalse(accepted)
        guard case .changed(_, _, _, let expected, _) = events.first else {
            return XCTFail("Damaged saved trust must require a changed-key decision")
        }
        XCTAssertEqual(expected, "damaged key")
    }

    func testFingerprintMatchesOpenSSHReferenceAndIgnoresComment() throws {
        let line = String(openSSHPublicKey: try publicKey(1))
        // Reference from ssh-keygen -lf for Ed25519 seed [1] x 32,
        // generated independently of NIOSSH and the app fingerprint code.
        let expected = "SHA256:fe85JkIjo8VPe+XqXJGH5Mau1EMFdK1OdKvJUFicyA8"
        XCTAssertEqual(HostKeyTrustValidator.fingerprint(of: line), expected)
        XCTAssertEqual(HostKeyTrustValidator.fingerprint(of: line + " public-comment"), expected)
    }
}
