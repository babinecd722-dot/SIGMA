import Foundation

enum TransferPipelineError: Error { case oversizedRead }

/// Request windows are bounded independently of file size. Reads are
/// committed in offset order, including servers that return short reads.
enum TransferPipeline {
    static let blockSize = 32_000
    static let window = 8

    static func write(
        next: () throws -> Data?,
        send: @escaping @Sendable (Data, UInt64) async throws -> Void,
        progress: (UInt64) -> Void = { _ in }
    ) async throws {
        try await withThrowingTaskGroup(of: Int.self) { group in
            var offset: UInt64 = 0
            var completed: UInt64 = 0
            var active = 0
            while true {
                try Task.checkCancellation()
                if active == window {
                    if let count = try await group.next() {
                        completed += UInt64(count)
                        progress(completed)
                        active -= 1
                    }
                }
                guard let data = try next(), !data.isEmpty else { break }
                let start = offset
                offset += UInt64(data.count)
                group.addTask {
                    try Task.checkCancellation()
                    try await send(data, start)
                    return data.count
                }
                active += 1
            }
            for try await count in group {
                completed += UInt64(count)
                progress(completed)
            }
        }
    }

    static func read(
        receive: @escaping @Sendable (UInt64, Int) async throws -> Data,
        consume: (Data) throws -> Void,
        progress: (UInt64) -> Void = { _ in }
    ) async throws {
        try await withThrowingTaskGroup(of: (UInt64, Data).self) { group in
            func enqueue(_ offset: UInt64) {
                group.addTask {
                    var data = Data()
                    while data.count < blockSize {
                        try Task.checkCancellation()
                        let wanted = blockSize - data.count
                        let part = try await receive(offset + UInt64(data.count), wanted)
                        guard part.count <= wanted else { throw TransferPipelineError.oversizedRead }
                        if part.isEmpty { break }
                        data.append(part)
                    }
                    return (offset, data)
                }
            }
            var nextOffset: UInt64 = 0
            for _ in 0..<window {
                enqueue(nextOffset)
                nextOffset += UInt64(blockSize)
            }
            var expected: UInt64 = 0
            var pending: [UInt64: Data] = [:]
            while let (offset, data) = try await group.next() {
                pending[offset] = data
                while let contiguous = pending.removeValue(forKey: expected) {
                    try Task.checkCancellation()
                    if !contiguous.isEmpty { try consume(contiguous) }
                    expected += UInt64(contiguous.count)
                    progress(expected)
                    if contiguous.count < blockSize {
                        group.cancelAll()
                        return
                    }
                    enqueue(nextOffset)
                    nextOffset += UInt64(blockSize)
                }
            }
        }
    }
}
