import XCTest
@testable import Terminal

final class AsyncOperationTests: XCTestCase {
    func testResultBeforeRegistrationIsNotLost() async throws {
        let gate = AsyncResultGate<Int>()
        gate.resolve(.success(42))
        let value = try await withCheckedThrowingContinuation { gate.install($0) }
        XCTAssertEqual(value, 42)
        gate.resolve(.success(99))
    }

    func testCancellationBeforeRegistrationIsNotLost() async {
        let gate = AsyncResultGate<Int>()
        gate.resolve(.failure(CancellationError()))
        do {
            _ = try await withCheckedThrowingContinuation { gate.install($0) }
            XCTFail("Cancelled waiter returned a value")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCompetingCompletionsResumeOnce() async throws {
        for _ in 0..<100 {
            let gate = AsyncResultGate<Int>()
            async let value: Int = withCheckedThrowingContinuation { gate.install($0) }
            await withTaskGroup(of: Void.self) { group in
                for n in 0..<8 { group.addTask { gate.resolve(.success(n)) } }
            }
            let answer = try await value
            XCTAssertTrue((0..<8).contains(answer))
        }
    }

    func testDeadlineActuallyReturns() async {
        do {
            _ = try await withOperationTimeout(.milliseconds(10)) {
                try await Task.sleep(for: .seconds(30))
                return 1
            }
            XCTFail("Expected deadline")
        } catch { XCTAssertTrue(error is OperationDeadlineExceeded) }
    }

    func testCancelledConsumerDoesNotCancelSharedWork() async throws {
        let finish = AsyncResultGate<Int>()
        let shared = Task<Int, Error> {
            try await withCheckedThrowingContinuation { finish.install($0) }
        }
        let consumer = Task { try await cancellableValue(of: shared) }
        consumer.cancel()
        do {
            _ = try await consumer.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(shared.isCancelled)
        finish.resolve(.success(7))
        let value = try await shared.value
        XCTAssertEqual(value, 7)
    }

    func testAlreadyCancelledTimeoutOperationReturnsCancellation() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await withOperationTimeout(.seconds(30)) {
                try await Task.sleep(for: .seconds(30))
                return 1
            }
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}
