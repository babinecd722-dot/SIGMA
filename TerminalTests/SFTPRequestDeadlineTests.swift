import XCTest
import NIO
import NIOEmbedded
import Logging
@testable import Citadel

final class SFTPRequestDeadlineTests: XCTestCase {
    func testUnansweredRequestExpiresAfterThirtySecondsAndReleasesChild() async throws {
        try await withClient { loop, channel, responses, client in
            let request = Task { try await client.getRealPath(atPath: ".") }
            await waitForRequest(responses, on: loop)
            XCTAssertEqual(responses.responses.count, 1)
            await loop.advanceTime(by: .seconds(29))
            XCTAssertEqual(responses.responses.count, 1, "A live request keeps its full response window")
            XCTAssertTrue(channel.isActive)
            await loop.advanceTime(by: .seconds(1))
            do {
                _ = try await request.value
                XCTFail("Unanswered request completed")
            } catch SFTPError.missingResponse {
                // Expected: an operation deadline after a successful INIT.
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(responses.responses.isEmpty)
            XCTAssertFalse(channel.isActive)
        }
    }

    func testReplyCancelsDeadlineWithoutClosingHealthyChannel() async throws {
        try await withClient { loop, channel, responses, client in
            let request = Task { try await client.remove(at: "/test-file") }
            await waitForRequest(responses, on: loop)
            let id = try XCTUnwrap(responses.responses.keys.first)
            responses.responses.removeValue(forKey: id)?.succeed(.status(.init(
                requestId: id, errorCode: .ok, message: "", languageTag: ""
            )))
            try await request.value
            await loop.advanceTime(by: .seconds(31))
            XCTAssertTrue(channel.isActive, "An old timer must not interrupt later transfers")
            XCTAssertTrue(responses.responses.isEmpty)
        }
    }

    private func waitForRequest(_ responses: SFTPResponses, on loop: NIOAsyncTestingEventLoop) async {
        for _ in 0..<100 {
            await loop.run()
            if !responses.responses.isEmpty { return }
            await Task.yield()
        }
        XCTFail("Request was not registered")
    }

    private func withClient(
        _ body: (NIOAsyncTestingEventLoop, NIOAsyncTestingChannel, SFTPResponses, SFTPClient) async throws -> Void
    ) async throws {
        let loop = NIOAsyncTestingEventLoop()
        let channel = NIOAsyncTestingChannel(loop: loop)
        try await channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 1)).get()
        let responses = SFTPResponses(sftpVersion: loop.makePromise())
        let client = SFTPClient(channel: channel, responses: responses, logger: .init(label: "test"))
        do {
            try await body(loop, channel, responses, client)
        } catch {
            responses.close()
            _ = try? await channel.finish(acceptAlreadyClosed: true)
            throw error
        }
        responses.close()
        _ = try await channel.finish(acceptAlreadyClosed: true)
    }
}
