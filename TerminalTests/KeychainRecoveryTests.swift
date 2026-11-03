import XCTest
import Security
@testable import Terminal

final class KeychainRecoveryTests: XCTestCase {
    func testInterruptedMigrationRestoresBeforeRemovingBackup() {
        let tag = "test.recovery.\(UUID().uuidString)"
        let backup = tag + Keychain.migrationBackupSuffix
        defer { Keychain.delete(tag); Keychain.delete(backup) }
        XCTAssertEqual(Keychain.save("original", tag: backup), errSecSuccess)
        XCTAssertEqual(Keychain.itemStatus(tag: tag), errSecItemNotFound)
        XCTAssertEqual(Keychain.recoverMigrationBackup(tag: tag), errSecSuccess)
        XCTAssertEqual(Keychain.loadString(tag: tag), "original")
        XCTAssertEqual(Keychain.itemStatus(tag: backup), errSecItemNotFound)
    }

    func testSuccessfulMigrationKeepsCurrentSecret() {
        let tag = "test.recovery.\(UUID().uuidString)"
        let backup = tag + Keychain.migrationBackupSuffix
        defer { Keychain.delete(tag); Keychain.delete(backup) }
        XCTAssertEqual(Keychain.save("current", tag: tag), errSecSuccess)
        XCTAssertEqual(Keychain.save("old", tag: backup), errSecSuccess)
        XCTAssertEqual(Keychain.recoverMigrationBackup(tag: tag), errSecSuccess)
        XCTAssertEqual(Keychain.loadString(tag: tag), "current")
        XCTAssertEqual(Keychain.itemStatus(tag: backup), errSecItemNotFound)
    }
}
