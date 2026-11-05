import XCTest
@testable import Terminal

final class KeyWorkTests: XCTestCase {
    func testNormalKeyWorkReturnsItsValue() async throws {
        let value = try await runKeyWork { 42 }
        XCTAssertEqual(value, 42)
    }

    func testCancellingOwnerStopsAlreadyRunningKeyWork() async {
        let began = expectation(description: "Key worker began")
        let task = Task {
            try await runKeyWork {
                began.fulfill()
                // Model a synchronous KDF's cooperative checks. A
                // bounded deadline makes the old detached-value bug
                // fail instead of hanging the test indefinitely.
                let deadline = Date().addingTimeInterval(2)
                while Date() < deadline {
                    try Task.checkCancellation()
                    Thread.sleep(forTimeInterval: 0.001)
                }
                return 1
            }
        }
        await fulfillment(of: [began], timeout: 1)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("An abandoned key operation published its result")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testAlreadyCancelledOwnerNeverStartsKeyWork() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await runKeyWork {
                XCTFail("A cancelled import started CPU work")
                return 1
            }
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}
