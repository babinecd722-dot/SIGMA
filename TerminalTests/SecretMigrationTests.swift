import XCTest
@testable import Terminal

final class SecretMigrationTests: XCTestCase {
    func testFailedInstallAndRestoreKeepLastSecretCopy() {
        var original: String? = "original"
        var backup: String?
        let status = SecretMigration.replace(stage: { backup = original; return 0 },
            removeOriginal: { original = nil; return 0 }, install: { -1 }, restore: { -2 },
            removeBackup: { backup = nil })
        XCTAssertEqual(status, -2)
        XCTAssertNil(original)
        XCTAssertEqual(backup, "original")
    }

    func testFailedInstallRestoresOriginalBeforeDroppingBackup() {
        var original: String? = "original"
        var backup: String?
        let status = SecretMigration.replace(stage: { backup = original; return 0 },
            removeOriginal: { original = nil; return 0 }, install: { -1 },
            restore: { original = backup; return 0 }, removeBackup: { backup = nil })
        XCTAssertEqual(status, -1)
        XCTAssertEqual(original, "original")
        XCTAssertNil(backup)
    }

    func testFailedBackupNeverTouchesOriginal() {
        let status = SecretMigration.replace(stage: { -1 },
            removeOriginal: { XCTFail("Original was touched"); return 0 },
            install: { XCTFail("Install after failed staging"); return 0 },
            restore: { XCTFail("Unnecessary restore"); return 0 }, removeBackup: {})
        XCTAssertEqual(status, -1)
    }

    func testSuccessfulMigrationKeepsNewSecret() {
        var original: String? = "original"
        var backup: String?
        let status = SecretMigration.replace(stage: { backup = original; return 0 },
            removeOriginal: { original = nil; return 0 },
            install: { original = "replacement"; return 0 },
            restore: { XCTFail("Unexpected rollback"); return 0 }, removeBackup: { backup = nil })
        XCTAssertEqual(status, 0)
        XCTAssertEqual(original, "replacement")
        XCTAssertNil(backup)
    }
}
