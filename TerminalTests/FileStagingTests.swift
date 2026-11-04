import XCTest
@testable import Terminal

final class FileStagingTests: XCTestCase {
    func testDownloadCleanupPreservesUserFilesDirectoriesAndSymlinks() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let keep = [".notes.partial-personal", ".file.partial-\(UUID().uuidString).txt",
                    ".partial-\(UUID().uuidString)", "report.txt"]
        for name in keep { try Data("USER DATA".utf8).write(to: root.appendingPathComponent(name)) }
        let stale = root.appendingPathComponent(".download.txt.partial-\(UUID().uuidString)")
        try Data("partial".utf8).write(to: stale)
        let folder = root.appendingPathComponent(".folder.partial-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("keep".utf8).write(to: folder.appendingPathComponent("child"))
        let link = root.appendingPathComponent(".link.partial-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("report.txt"))

        FileStaging.purgeDownloadPartials(in: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        for name in keep {
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(name)), Data("USER DATA".utf8))
        }
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("child")), Data("keep".utf8))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), root.appendingPathComponent("report.txt").path)
    }

    func testPreviewCleanupOnlyRemovesGeneratedDirectories() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let stale = root.appendingPathComponent("preview-\(UUID().uuidString)")
        let user = root.appendingPathComponent("preview-important")
        for folder in [stale, user] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try Data("data".utf8).write(to: folder.appendingPathComponent("child"))
        }
        let file = root.appendingPathComponent("preview-\(UUID().uuidString)")
        try Data("keep".utf8).write(to: file)
        let link = root.appendingPathComponent("preview-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: user)

        FileStaging.purgePreviewFolders(in: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertEqual(try Data(contentsOf: user.appendingPathComponent("child")), Data("data".utf8))
        XCTAssertEqual(try Data(contentsOf: file), Data("keep".utf8))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), user.path)
    }

    private func temporaryFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("staging-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}
