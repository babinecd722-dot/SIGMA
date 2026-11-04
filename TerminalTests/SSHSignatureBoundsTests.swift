import XCTest
import NIO
@testable import NIOSSH

/// Wire-level coverage for the pre-authentication signature decoder.
/// A peer must be rejected before oversized integers reach stack storage.
final class SSHSignatureBoundsTests: XCTestCase {
    private let curves: [(String, Int)] = [
        ("ecdsa-sha2-nistp256", 32),
        ("ecdsa-sha2-nistp384", 48),
        ("ecdsa-sha2-nistp521", 66)
    ]

    private func signature(_ algorithm: String, r: [UInt8], s: [UInt8]) -> ByteBuffer {
        var integers = ByteBufferAllocator().buffer(capacity: r.count + s.count + 8)
        integers.writeSSHString(r)
        integers.writeSSHString(s)
        var wire = ByteBufferAllocator().buffer(capacity: integers.readableBytes + algorithm.utf8.count + 8)
        wire.writeSSHString(algorithm.utf8)
        wire.writeSSHString(&integers)
        return wire
    }

    func testOversizedComponentsAreRejectedForEveryCurve() {
        for (algorithm, width) in curves {
            for length in [width + 1, 4096] {
                let valid = [UInt8](repeating: 1, count: width)
                let oversized = [UInt8](repeating: 1, count: length)
                for (r, s) in [(oversized, valid), (valid, oversized)] {
                    var wire = signature(algorithm, r: r, s: s)
                    let originalIndex = wire.readerIndex
                    XCTAssertThrowsError(try wire.readSSHSignature(), algorithm) { error in
                        XCTAssertEqual((error as? NIOSSHError)?.type, .invalidSSHMessage)
                    }
                    XCTAssertEqual(wire.readerIndex, originalIndex, "Failed parsing must rewind the buffer")
                }
            }
        }
    }

    func testLeadingZeroCannotHideAnOversizedComponent() {
        for (algorithm, width) in curves {
            let oversized = [UInt8(0)] + [UInt8](repeating: 0x80, count: width + 1)
            let valid = [UInt8](repeating: 1, count: width)
            for (r, s) in [(oversized, valid), (valid, oversized)] {
                var wire = signature(algorithm, r: r, s: s)
                XCTAssertThrowsError(try wire.readSSHSignature()) { error in
                    XCTAssertEqual((error as? NIOSSHError)?.type, .invalidSSHMessage)
                }
            }
        }
    }

    func testAlignedAndSignPrefixedComponentsRemainAccepted() throws {
        for (algorithm, width) in curves {
            let aligned = [UInt8](repeating: 1, count: width)
            for (r, s) in [(aligned, aligned), ([0] + aligned, aligned), (aligned, [0] + aligned)] {
                var wire = signature(algorithm, r: r, s: s)
                XCTAssertNotNil(try wire.readSSHSignature(), algorithm)
                XCTAssertEqual(wire.readableBytes, 0)
            }
        }
    }
}
