import Combine
import Foundation
import UIKit

/// Fires `body` on the main actor when protected data becomes available —
/// the hook every store uses to retry a `locked` persistence file.
private func onProtectedDataUnlock(_ body: @escaping @MainActor @Sendable () -> Void) -> NSObjectProtocol {
    NotificationCenter.default.addObserver(
        forName: UIApplication.protectedDataDidBecomeAvailableNotification,
        object: nil,
        queue: .main
    ) { _ in
        Task { @MainActor in body() }
    }
}

@MainActor
final class ProfilesStore: ObservableObject {
    @Published private(set) var profiles: [ServerProfile]
    /// Set whenever a persistence operation fails — alongside a `false`
    /// return so the UI can surface the failure instead of a fake "saved".
    @Published private(set) var storageError: Error?
    /// The on-disk file is corrupt, locked, or from a newer schema.
    var storageBlocked: Bool { !store.writable }
    /// Raw bytes of a blocked file — for a user-triggered export or
    /// rescue path; nil unless the store is corrupt/newer-schema.
    var unrecoverableData: Data? { store.unrecoverableFileContents() }

    private let store: JSONStore<[ServerProfile]>
    private var unlockObserver: NSObjectProtocol? = nil

    init(directory: URL? = nil) {
        let store = JSONStore<[ServerProfile]>("profiles", initial: [], directory: directory)
        self.store = store
        profiles = store.load()
        storageError = store.lastError
        unlockObserver = onProtectedDataUnlock { [weak self] in
            self?.reloadAfterUnlock()
        }
    }

    /// Retries a data-protection-locked file — and ONLY that state;
    /// corrupt/newer files are never touched automatically.
    func reloadAfterUnlock() {
        guard store.retryAfterUnlock() else { return }
        profiles = store.load()
        storageError = store.lastError
    }

    /// true only when the new list actually hit disk — the published
    /// array is updated after persistence, never before.
    @discardableResult
    func save(_ profile: ServerProfile) -> Bool {
        var candidate = profiles
        if let idx = candidate.firstIndex(where: { $0.id == profile.id }) {
            candidate[idx] = profile
        } else {
            candidate.append(profile)
        }
        guard store.save(candidate) else {
            storageError = store.lastError
            return false
        }
        profiles = candidate
        storageError = nil
        return true
    }

    /// Metadata removal is persisted FIRST; only then is the Keychain
    /// secret deleted. A failure can leave an orphaned password (swept
    /// later), never a profile pointing at a deleted secret.
    @discardableResult
    func delete(_ profile: ServerProfile) -> Bool {
        var candidate = profiles
        candidate.removeAll { $0.id == profile.id }
        guard store.save(candidate) else {
            storageError = store.lastError
            return false
        }
        profiles = candidate
        let status = Keychain.delete("password.\(profile.id.uuidString)")
        guard status == errSecSuccess || status == errSecItemNotFound else {
            storageError = NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            return false
        }
        storageError = nil
        return true
    }

    @discardableResult
    func markConnected(_ id: UUID) -> Bool {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return true }
        var candidate = profiles
        candidate[idx].lastConnected = Date()
        guard store.save(candidate) else {
            storageError = store.lastError
            return false
        }
        profiles = candidate
        storageError = nil
        return true
    }
}

@MainActor
final class KeysStore: ObservableObject {
    @Published private(set) var keys: [StoredSSHKey]
    @Published private(set) var storageError: Error?
    var storageBlocked: Bool { !store.writable }
    var unrecoverableData: Data? { store.unrecoverableFileContents() }

    private let store: JSONStore<[StoredSSHKey]>
    private var unlockObserver: NSObjectProtocol? = nil

    init(directory: URL? = nil) {
        let store = JSONStore<[StoredSSHKey]>("keys", initial: [], directory: directory)
        self.store = store
        keys = store.load()
        storageError = store.lastError
        unlockObserver = onProtectedDataUnlock { [weak self] in
            self?.reloadAfterUnlock()
        }
        repairPublicKeyLines()
    }

    func reloadAfterUnlock() {
        guard store.retryAfterUnlock() else { return }
        keys = store.load()
        storageError = store.lastError
        repairPublicKeyLines()
    }

    /// Keys generated before the publicKeyLine fix carry a double-
    /// wrapped blob — `type base64(wire(type, wire(blob)))`. Unwrap
    /// one layer back to `type base64(blob)`; anything not matching
    /// that exact shape is left alone (imported keys were never bad).
    private func repairPublicKeyLines() {
        var repaired = keys
        var changed = false
        for i in repaired.indices {
            let line = repaired[i].publicKeyOpenSSH
            let parts = line.split(separator: " ")
            guard parts.count >= 2,
                  let outer = Data(base64Encoded: String(parts[1])) else { continue }
            var reader = SSHWireReader(outer)
            guard let outerType = try? reader.readText(),
                  outerType == parts[0],
                  let inner = try? reader.readString(),
                  reader.remaining == 0 else { continue }
            var innerReader = SSHWireReader(inner)
            guard let innerType = try? innerReader.readText(),
                  innerType == parts[0] else { continue }
            repaired[i].publicKeyOpenSSH = "\(parts[0]) \(inner.base64EncodedString())"
            changed = true
        }
        guard changed, store.save(repaired) else { return }
        keys = repaired
    }

    @discardableResult
    func save(_ key: StoredSSHKey) -> Bool {
        var candidate = keys
        if let idx = candidate.firstIndex(where: { $0.id == key.id }) {
            candidate[idx] = key
        } else {
            candidate.append(key)
        }
        guard store.save(candidate) else {
            storageError = store.lastError
            return false
        }
        keys = candidate
        storageError = nil
        return true
    }

    /// The metadata removal is committed to disk BEFORE the Keychain
    /// secret goes away — the reverse order could leave an entry that
    /// points at already-deleted material.
    @discardableResult
    func delete(_ key: StoredSSHKey) -> Bool {
        var candidate = keys
        candidate.removeAll { $0.id == key.id }
        guard store.save(candidate) else {
            storageError = store.lastError
            return false
        }
        keys = candidate
        let status = KeyVault.removeStoredSecrets(for: key)
        guard status == errSecSuccess else {
            // The secret may now be orphaned; sweep it rather than
            // resurrecting the metadata entry.
            storageError = NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            return false
        }
        storageError = nil
        return true
    }

    /// Sweeps Keychain material whose tag no stored key references —
    /// e.g. secrets orphaned by a crash between metadata delete and
    /// secret delete. Returns the count removed. Never runs against an
    /// unreadable store: a corrupt `keys` file decodes to an empty
    /// list, and sweeping from it would wipe every stored secret.
    @discardableResult
    func removeOrphanedSecrets() -> Int {
        guard storageError == nil, unrecoverableData == nil else { return 0 }
        return KeyVault.removeOrphanedSecrets(keeping: Set(keys.flatMap {
            [$0.keychainTag, $0.passphraseTag]
        }))
    }

    func key(id: UUID?) -> StoredSSHKey? {
        guard let id else { return nil }
        return keys.first { $0.id == id }
    }
}

@MainActor
final class KnownHostsStore: ObservableObject {
    @Published private(set) var hosts: [KnownHost]
    @Published private(set) var storageError: Error?
    var storageBlocked: Bool { !store.writable }
    var unrecoverableData: Data? { store.unrecoverableFileContents() }

    private let store: JSONStore<[KnownHost]>
    private var unlockObserver: NSObjectProtocol? = nil

    init(directory: URL? = nil) {
        let store = JSONStore<[KnownHost]>("known_hosts", initial: [], directory: directory)
        self.store = store
        hosts = store.load()
        storageError = store.lastError
        unlockObserver = onProtectedDataUnlock { [weak self] in
            self?.reloadAfterUnlock()
        }
    }

    func reloadAfterUnlock() {
        guard store.retryAfterUnlock() else { return }
        hosts = store.load()
        storageError = store.lastError
    }

    /// Hostnames are case-insensitive — normalize before keying.
    private func key(_ host: String, _ port: Int) -> String {
        "\(host.lowercased()):\(port)"
    }

    func known(host: String, port: Int) -> KnownHost? {
        hosts.first { $0.key == key(host, port) }
    }

    @discardableResult
    func trust(host: String, port: Int, publicKeyOpenSSH: String) -> Bool {
        var candidate = hosts
        if let idx = candidate.firstIndex(where: { $0.key == key(host, port) }) {
            candidate[idx].publicKeyOpenSSH = publicKeyOpenSSH
            candidate[idx].lastSeen = Date()
        } else {
            candidate.append(KnownHost(host: host.lowercased(), port: port, publicKeyOpenSSH: publicKeyOpenSSH))
        }
        guard store.save(candidate) else {
            storageError = store.lastError
            return false
        }
        hosts = candidate
        storageError = nil
        return true
    }

    @discardableResult
    func reset(host: String, port: Int) -> Bool {
        var candidate = hosts
        candidate.removeAll { $0.key == key(host, port) }
        guard store.save(candidate) else {
            storageError = store.lastError
            return false
        }
        hosts = candidate
        storageError = nil
        return true
    }
}

@MainActor
final class SnippetsStore: ObservableObject {
    @Published private(set) var snippets: [Snippet]
    @Published private(set) var storageError: Error?
    var storageBlocked: Bool { !store.writable }
    var unrecoverableData: Data? { store.unrecoverableFileContents() }

    private let store: JSONStore<[Snippet]>
    private var unlockObserver: NSObjectProtocol? = nil

    init(directory: URL? = nil) {
        let store = JSONStore<[Snippet]>("snippets", initial: [], directory: directory)
        self.store = store
        snippets = store.load()
        storageError = store.lastError
        unlockObserver = onProtectedDataUnlock { [weak self] in
            self?.reloadAfterUnlock()
        }
    }

    func reloadAfterUnlock() {
        guard store.retryAfterUnlock() else { return }
        snippets = store.load()
        storageError = store.lastError
    }

    @discardableResult
    func save(_ snippet: Snippet) -> Bool {
        var candidate = snippets
        if let idx = candidate.firstIndex(where: { $0.id == snippet.id }) {
            candidate[idx] = snippet
        } else {
            candidate.append(snippet)
        }
        guard store.save(candidate) else {
            storageError = store.lastError
            return false
        }
        snippets = candidate
        storageError = nil
        return true
    }

    @discardableResult
    func delete(_ snippet: Snippet) -> Bool {
        var candidate = snippets
        candidate.removeAll { $0.id == snippet.id }
        guard store.save(candidate) else {
            storageError = store.lastError
            return false
        }
        snippets = candidate
        storageError = nil
        return true
    }

    /// One write for reorder/move operations.
    @discardableResult
    func replaceAll(_ snippets: [Snippet]) -> Bool {
        guard store.save(snippets) else {
            storageError = store.lastError
            return false
        }
        self.snippets = snippets
        storageError = nil
        return true
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    /// Reads/writes through `_settings`, which stays @Published so the
    /// UI observes as before. The set path persists FIRST: a failed
    /// save is refused outright — the published value never moves to
    /// a state that didn't hit disk (no fake "saved" toggle).
    var settings: AppSettings {
        get { _settings }
        set {
            let value = newValue.sanitized
            guard store.save(value) else {
                storageError = store.lastError
                return
            }
            _settings = value
            storageError = nil
        }
    }
    var requiresUnlock: Bool { settings.requireBiometry || storageBlocked }

    @discardableResult
    func resetPreservingBackup() -> Bool {
        guard store.resetPreservingBackup() else {
            storageError = store.lastError
            return false
        }
        _settings = AppSettings()
        storageError = nil
        return true
    }

    @Published private var _settings: AppSettings
    @Published private(set) var storageError: Error?
    var storageBlocked: Bool { !store.writable }
    var unrecoverableData: Data? { store.unrecoverableFileContents() }

    private let store: JSONStore<AppSettings>
    private var unlockObserver: NSObjectProtocol? = nil

    init(directory: URL? = nil) {
        let store = JSONStore<AppSettings>(
            "AppSettings",
            initial: AppSettings(),
            directory: directory,
            legacyDecode: SettingsCodec.decodeLegacy
        )
        self.store = store
        _settings = store.load().sanitized
        storageError = store.lastError
        unlockObserver = onProtectedDataUnlock { [weak self] in
            self?.reloadAfterUnlock()
        }
    }

    func reloadAfterUnlock() {
        guard store.retryAfterUnlock() else { return }
        _settings = store.load().sanitized
        storageError = store.lastError
    }
}
