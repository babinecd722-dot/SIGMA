import XCTest
@testable import Terminal

final class KeyExportStagingTests: XCTestCase {
    func testSameNameExportsArePrivateDistinctAndCleanedTogether() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try KeyExportStaging.write("TEST FIRST", name: "same", in: root)
        let second = try KeyExportStaging.write("TEST SECOND", name: "same", in: root)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "TEST FIRST")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "TEST SECOND")
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: first.deletingLastPathComponent().path)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: first.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        // Simulator Foundation does not expose NSFileProtectionKey.
        // Keep this device-only assertion alongside the cross-platform
        // mode, content, isolation and cleanup checks above/below.
        #if os(iOS) && !targetEnvironment(simulator)
        let protection = fileAttributes[.protectionKey]
        let protectionName = (protection as? FileProtectionType)?.rawValue ?? (protection as? String)
        XCTAssertEqual(protectionName, FileProtectionType.complete.rawValue)
        #endif
        KeyExportStaging.remove(first, in: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.deletingLastPathComponent().path))
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "TEST SECOND")
        KeyExportStaging.remove(second, in: root)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testExportNameCannotEscapeItsPrivateDirectory() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try KeyExportStaging.write("TEST", name: "../../folder\\name\n🔑", in: root)
        XCTAssertEqual(file.deletingLastPathComponent().deletingLastPathComponent(), root)
        XCTAssertTrue(KeyExportStaging.isExportFolderName(file.deletingLastPathComponent().lastPathComponent))
        XCTAssertFalse(file.lastPathComponent.contains("\n"))
        XCTAssertFalse(file.lastPathComponent.contains("\\"))
    }

    func testCrashCleanupPreservesLookalikesFilesAndSymlinks() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let stale = try KeyExportStaging.write("TEST", name: "key", in: root)
        let personal = root.appendingPathComponent("key-export-personal")
        try FileManager.default.createDirectory(at: personal, withIntermediateDirectories: false)
        try Data("KEEP".utf8).write(to: personal.appendingPathComponent("user"))
        let regular = root.appendingPathComponent("key-export-\(UUID().uuidString)")
        try Data("KEEP".utf8).write(to: regular)
        let symlink = root.appendingPathComponent("key-export-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: personal)
        let unrelatedKey = root.appendingPathComponent("personal.key")
        try Data("KEEP".utf8).write(to: unrelatedKey)

        FileStaging.purgeKeyExportFolders(in: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.deletingLastPathComponent().path))
        XCTAssertEqual(try String(contentsOf: personal.appendingPathComponent("user"), encoding: .utf8), "KEEP")
        XCTAssertEqual(try String(contentsOf: regular, encoding: .utf8), "KEEP")
        XCTAssertEqual(try String(contentsOf: unrelatedKey, encoding: .utf8), "KEEP")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: symlink.path), personal.path)
    }

    private func temporaryFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("key-export-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}
