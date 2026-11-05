import XCTest
import Crypto
@testable import Terminal

/// A deterministic, bounded malformed-input corpus. It covers the actual
/// OpenSSH parser and wire reader; encrypted KDF interop has separate fixtures.
final class KeyParserBoundaryTests: XCTestCase {
    func testEveryTruncationOfUnencryptedKeyIsRejected() throws {
        let blob = try fixture()
        for count in 0..<blob.count {
            XCTAssertThrowsError(try OpenSSHKeyParser.parse(pem(Data(blob.prefix(count))), passphrase: nil), "Accepted truncation at \(count)")
        }
        XCTAssertEqual(try OpenSSHKeyParser.parse(pem(blob), passphrase: nil).privateMaterial, Data(repeating: 7, count: 32))
    }

    func testSingleBitMutationCorpusRejectsCorruptionOrPreservesKeyIdentity() throws {
        let blob = try fixture()
        let control = try OpenSSHKeyParser.parse(pem(blob), passphrase: nil)
        for index in blob.indices {
            for bit in 0..<8 {
                var mutated = blob
                mutated[index] ^= UInt8(1 << bit)
                do {
                    let result = try OpenSSHKeyParser.parse(pem(mutated), passphrase: nil)
                    // Comment-only mutations can be legitimate. A
                    // successful parse must still describe this key.
                    XCTAssertEqual(result.privateMaterial, control.privateMaterial, "Key changed at \(index):\(bit)")
                    XCTAssertEqual(result.publicKeyLine, control.publicKeyLine, "Public key changed at \(index):\(bit)")
                } catch {
                    XCTAssertTrue(error is SSHKeyImportError || error is CancellationError)
                }
            }
        }
    }

    func testWireLengthAndNegativeCountBoundariesRejectWithoutConsumingPayload() throws {
        for length: UInt32 in [1, 4, 65_536, .max] {
            var writer = SSHWireWriter()
            writer.writeUInt32(length)
            var reader = SSHWireReader(writer.data)
            XCTAssertThrowsError(try reader.readString())
            XCTAssertEqual(reader.remaining, 0)
        }
        var reader = SSHWireReader(Data([1, 2, 3]))
        XCTAssertThrowsError(try reader.readBytes(Int.min))
        XCTAssertThrowsError(try reader.readBytes(Int.max))
        XCTAssertEqual(reader.remaining, 3)
        XCTAssertEqual(try reader.readBytes(3), Data([1, 2, 3]))
    }

    private func fixture() throws -> Data {
        let seed = Data(repeating: 7, count: 32)
        let key = try Crypto.Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        let publicKey = key.publicKey.rawRepresentation
        let publicBlob = SSHWireWriter.ed25519PublicKeyBlob(publicKey)
        var inner = SSHWireWriter()
        inner.writeUInt32(0x12345678)
        inner.writeUInt32(0x12345678)
        inner.writeText("ssh-ed25519")
        inner.writeString(publicKey)
        inner.writeString(seed + publicKey)
        inner.writeText("parser-corpus")
        var section = inner.data
        for byte in 1...(8 - section.count % 8) { section.append(UInt8(byte)) }
        var outer = SSHWireWriter()
        outer.writeText("none")
        outer.writeText("none")
        outer.writeString(Data())
        outer.writeUInt32(1)
        outer.writeString(publicBlob)
        outer.writeString(section)
        return Data("openssh-key-v1\0".utf8) + outer.data
    }

    private func pem(_ blob: Data) -> String {
        "-----BEGIN OPENSSH PRIVATE KEY-----\n" + blob.base64EncodedString() + "\n-----END OPENSSH PRIVATE KEY-----"
    }
}
