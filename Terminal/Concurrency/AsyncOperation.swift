import Foundation

/// A result can arrive before or after its waiter, including cancellation
/// before the cancellation handler's operation begins. Never resume under
/// the lock: resuming may schedule arbitrary code.
final class AsyncResultGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func resolve(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let waiter = continuation
        continuation = nil
        lock.unlock()
        waiter?.resume(with: result)
    }
}

struct OperationDeadlineExceeded: Error, Sendable {}

/// A deadline must not await a child that ignores cancellation. Both the
/// deadline and work tasks are cancelled when the waiter leaves.
func withOperationTimeout<Value: Sendable>(
    _ timeout: Duration,
    _ operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try Task.checkCancellation()
    let gate = AsyncResultGate<Value>()
    let work = Task {
        do { gate.resolve(.success(try await operation())) }
        catch { gate.resolve(.failure(error)) }
    }
    let timer = Task {
        do { try await Task.sleep(for: timeout) }
        catch { return }
        gate.resolve(.failure(OperationDeadlineExceeded()))
    }
    defer { work.cancel(); timer.cancel() }
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { gate.install($0) }
    } onCancel: {
        gate.resolve(.failure(CancellationError()))
        work.cancel()
        timer.cancel()
    }
}

/// Abandon this consumer's wait without cancelling a shared operation.
func cancellableValue<Value: Sendable>(of task: Task<Value, Error>) async throws -> Value {
    try Task.checkCancellation()
    let gate = AsyncResultGate<Value>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)
            Task { gate.resolve(await task.result) }
        }
    } onCancel: {
        gate.resolve(.failure(CancellationError()))
    }
}
