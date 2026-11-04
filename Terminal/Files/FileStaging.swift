import Foundation

/// Restrict cleanup to the exact staging name formats and item types.
/// Documents is also writable through Files/Finder: a substring match
/// alone must never authorize deletion of a user's file or folder.
enum FileStaging {
    static func purgeDownloadPartials(in directory: URL) {
        purge(in: directory, directories: false) { name in
            guard name.hasPrefix("."),
                  let marker = name.range(of: ".partial-", options: .backwards),
                  marker.lowerBound > name.index(after: name.startIndex) else { return false }
            return isGeneratedUUID(String(name[marker.upperBound...]))
        }
    }

    static func purgePreviewFolders(in directory: URL) {
        purge(in: directory, directories: true) { name in
            guard name.hasPrefix("preview-") else { return false }
            return isGeneratedUUID(String(name.dropFirst("preview-".count)))
        }
    }

    private static func isGeneratedUUID(_ value: String) -> Bool {
        guard let id = UUID(uuidString: value) else { return false }
        return value == id.uuidString
    }

    private static func purge(in directory: URL, directories: Bool, matches: (String) -> Bool) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys)
        ) else { return }
        for item in items where matches(item.lastPathComponent) {
            guard let values = try? item.resourceValues(forKeys: keys),
                  values.isSymbolicLink != true,
                  directories ? values.isDirectory == true : values.isRegularFile == true else { continue }
            try? FileManager.default.removeItem(at: item)
        }
    }
}
