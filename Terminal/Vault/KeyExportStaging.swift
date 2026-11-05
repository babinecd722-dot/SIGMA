import Foundation

/// A private key export has a private, unique directory. A display name is
/// never a shared temporary-file identity, and crash leftovers are recognizable
/// without deleting arbitrary `.key` files from the temporary directory.
enum KeyExportStaging {
    static func write(_ pem: String, name: String, in directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        try Task.checkCancellation()
        let folder = directory.appendingPathComponent("key-export-\(UUID().uuidString)", isDirectory: true)
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: attributes)
        do {
            let safe = String(name.unicodeScalars.filter {
                !CharacterSet.controlCharacters.contains($0) && $0 != "/" && $0 != "\\" && $0 != ":"
            }.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
            let file = folder.appendingPathComponent(safe.isEmpty ? "key" : safe).appendingPathExtension("key")
            try Data(pem.utf8).write(to: file, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            try Task.checkCancellation()
            return file
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    static func remove(_ file: URL, in directory: URL = FileManager.default.temporaryDirectory) {
        let folder = file.deletingLastPathComponent().standardizedFileURL
        guard folder.deletingLastPathComponent() == directory.standardizedFileURL,
              isExportFolderName(folder.lastPathComponent),
              let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    static func isExportFolderName(_ name: String) -> Bool {
        let prefix = "key-export-"
        guard name.hasPrefix(prefix), let id = UUID(uuidString: String(name.dropFirst(prefix.count))) else { return false }
        return name == prefix + id.uuidString
    }
}
