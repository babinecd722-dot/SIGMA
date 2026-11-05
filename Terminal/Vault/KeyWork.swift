import Foundation

/// CPU-heavy key work belongs off the caller's actor, but its cancellation
/// still belongs to that caller. Awaiting a detached task's value alone does
/// not cancel the worker when the export/import sheet goes away.
func runKeyWork<Value: Sendable>(
    _ operation: @escaping @Sendable () throws -> Value
) async throws -> Value {
    try Task.checkCancellation()
    let worker = Task.detached(priority: .userInitiated) {
        try Task.checkCancellation()
        let result = try operation()
        try Task.checkCancellation()
        return result
    }
    return try await withTaskCancellationHandler {
        let result = try await worker.value
        try Task.checkCancellation()
        return result
    } onCancel: {
        worker.cancel()
    }
}
