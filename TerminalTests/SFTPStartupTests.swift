import XCTest
import NIO
import NIOEmbedded
import NIOSSH
import Logging
import NIOConcurrencyHelpers
@testable import Citadel

final class SFTPStartupTests: XCTestCase {
    func testRejectedSubsystemFailsVersionAndClosesOnlyItsChild() throws {
        let loop = EmbeddedEventLoop()
        let responses = SFTPResponses(sftpVersion: loop.makePromise())
        let result = NIOLockedValueBox<Error?>(nil)
        responses.sftpVersion.futureResult.whenFailure { error in
            result.withLockedValue { $0 = error }
        }
        let child = EmbeddedChannel(
            handler: SFTPClientInboundHandler(responses: responses, logger: .init(label: "test")),
            loop: loop
        )
        let closed = NIOLockedValueBox(false)
        child.closeFuture.whenSuccess { closed.withLockedValue { $0 = true } }
        child.pipeline.fireUserInboundEventTriggered(ChannelFailureEvent())
        loop.run()
        XCTAssertNotNil(result.withLockedValue { $0 }, "Refusal must not wait for a VERSION packet that will never arrive")
        XCTAssertTrue(closed.withLockedValue { $0 }, "The abandoned SFTP child must be released")
        responses.close()
        _ = try child.finish(acceptAlreadyClosed: true)
    }
}
