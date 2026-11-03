import XCTest
@testable import Terminal

final class TransferPipelineTests: XCTestCase {
    func testOutOfOrderShortReadsPreserveEveryByte() async throws {
        let source = Data((0..<150_001).map { UInt8($0 % 251) })
        var output = Data()
        var reported: UInt64 = 0
        try await TransferPipeline.read(receive: { offset, length in
            if offset == 0 { try await Task.sleep(for: .milliseconds(10)) }
            guard offset < source.count else { return Data() }
            let start = Int(offset)
            return Data(source[start..<min(source.count, start + min(length, 997))])
        }, consume: { output.append($0) }, progress: { reported = $0 })
        XCTAssertEqual(output, source)
        XCTAssertEqual(reported, UInt64(source.count))
    }

    func testEmptyFileEndsWithoutInventingBytes() async throws {
        var output = Data()
        try await TransferPipeline.read(receive: { _, _ in Data() }, consume: { output.append($0) })
        XCTAssertTrue(output.isEmpty)
    }

    func testOversizedServerResponseIsRejected() async {
        do {
            try await TransferPipeline.read(receive: { _, wanted in
                Data(repeating: 0, count: wanted + 1)
            }, consume: { _ in XCTFail("Invalid response was committed") })
            XCTFail("Expected invalid response")
        } catch { XCTAssertTrue(error is TransferPipelineError) }
    }

    func testPipelinedWritesUseDistinctOffsetsAndWaitForAcknowledgements() async throws {
        actor Sink {
            var chunks: [UInt64: Data] = [:]
            func accept(_ bytes: Data, at offset: UInt64) { chunks[offset] = bytes }
            func joined() -> Data {
                chunks.keys.sorted().reduce(into: Data()) { $0.append(chunks[$1]!) }
            }
        }
        let sink = Sink()
        let source = Data((0..<300_007).map { UInt8($0 % 251) })
        var offset = 0
        var progress: UInt64 = 0
        try await TransferPipeline.write(next: {
            guard offset < source.count else { return nil }
            let end = min(source.count, offset + TransferPipeline.blockSize)
            defer { offset = end }
            return Data(source[offset..<end])
        }, send: { data, offset in
            if offset == 0 { try await Task.sleep(for: .milliseconds(10)) }
            await sink.accept(data, at: offset)
        }, progress: { progress = $0 })
        let copied = await sink.joined()
        XCTAssertEqual(copied, source)
        XCTAssertEqual(progress, UInt64(source.count))
    }
}
