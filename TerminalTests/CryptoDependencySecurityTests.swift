import XCTest
import Foundation
import Crypto
import _CryptoExtras

final class CryptoDependencySecurityTests: XCTestCase {
    func testMalformedRSADERThrowsRepeatedlyWithoutDoubleFree() {
        let invalid = Data([0x30, 0x06, 0x02, 0x01, 0x00, 0x02, 0x01, 0x00])
        for _ in 0..<16 {
            XCTAssertThrowsError(try _RSA.Signing.PublicKey(derRepresentation: invalid))
        }
    }

    func testMalformedRSAPEMThrowsRepeatedlyWithoutDoubleFree() {
        let invalid = """
        -----BEGIN PUBLIC KEY-----
        MAYCAQACAQ==
        -----END PUBLIC KEY-----
        """
        for _ in 0..<16 {
            XCTAssertThrowsError(try _RSA.Signing.PublicKey(pemRepresentation: invalid))
        }
    }

    func testVOPRFRejectsInputBeyondRFCMaximum() throws {
        let key = P384._VOPRF.PrivateKey()
        let oversized = Data(repeating: 1, count: 65_536)
        XCTAssertThrowsError(try key.publicKey.blind(oversized)) { error in
            XCTAssertEqual(error as? CryptoKitError, .incorrectParameterSize)
        }
        XCTAssertThrowsError(try key.evaluate(oversized)) { error in
            XCTAssertEqual(error as? CryptoKitError, .incorrectParameterSize)
        }
    }

    func testVOPRFRoundTripAcceptsInputsThroughRFCMaximum() throws {
        let key = P384._VOPRF.PrivateKey()
        for input in [Data(), Data("terminal".utf8), Data(repeating: 1, count: 65_535)] {
            let blinded = try key.publicKey.blind(input)
            let evaluation = try key.evaluate(blinded.blindedElement)
            let finalized = try key.publicKey.finalize(blinded, using: evaluation)
            XCTAssertEqual(finalized, try key.evaluate(input))
        }
    }
}
