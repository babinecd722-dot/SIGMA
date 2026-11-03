import XCTest
import NIO
import NIOEmbedded
import NIOConcurrencyHelpers
import NIOSSH
@testable import Citadel

final class HandshakeDeadlineTests: XCTestCase {
    func testProtocolSilenceStillTimesOut() {
        let loop = EmbeddedEventLoop()
        let handshake = ClientHandshakeHandler(eventLoop: loop, loginTimeout: .seconds(30))
        let failed = NIOLockedValueBox(false)
        handshake.authenticated.whenFailure { _ in failed.withLockedValue { $0 = true } }
        loop.advanceTime(by: .seconds(31))
        XCTAssertTrue(failed.withLockedValue { $0 })
    }

    func testApprovalPausesEvenBeforeQueuedDeadlineStarts() {
        let loop = EmbeddedEventLoop()
        let handshake = ClientHandshakeHandler(eventLoop: loop, loginTimeout: .seconds(30))
        let completed = NIOLockedValueBox(false)
        handshake.authenticated.whenComplete { _ in completed.withLockedValue { $0 = true } }
        // Pause before the initializer's queued arm operation executes.
        handshake.pauseTimeout()
        loop.advanceTime(by: .seconds(120))
        XCTAssertFalse(completed.withLockedValue { $0 })
        handshake.resumeTimeout()
        loop.advanceTime(by: .seconds(29))
        XCTAssertFalse(completed.withLockedValue { $0 })
        loop.advanceTime(by: .seconds(2))
        XCTAssertTrue(completed.withLockedValue { $0 })
    }

    func testAuthenticationSuccessCompletesHandshake() throws {
        let loop = EmbeddedEventLoop()
        let handshake = ClientHandshakeHandler(eventLoop: loop, loginTimeout: .seconds(30))
        let channel = EmbeddedChannel(handler: handshake, loop: loop)
        defer { _ = try? channel.finish() }
        let succeeded = NIOLockedValueBox(false)
        handshake.authenticated.whenSuccess { succeeded.withLockedValue { $0 = true } }
        channel.pipeline.fireUserInboundEventTriggered(UserAuthSuccessEvent())
        loop.run()
        XCTAssertTrue(succeeded.withLockedValue { $0 })
        handshake.resumeTimeout()
        loop.advanceTime(by: .seconds(120))
        XCTAssertTrue(succeeded.withLockedValue { $0 })
    }
}
