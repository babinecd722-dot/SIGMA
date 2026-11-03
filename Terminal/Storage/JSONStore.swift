import Foundation

/// Versioned JSON persistence. Writes are atomic and always create the
/// file; an unreadable or corrupt file locks the store so a later save
/// can never clobber the user's data with an empty payload.
final class JSONStore<T: Codable> {
    /// Why a store is (or isn't) writable — and whether it can recover.
    enum State {
        /// No file yet — a fresh install, fully writable.
        case missing
        /// Decoded fine, or the last save succeeded — writable.
        case ready
        /// File exists but data protection denied the read (pre-first
        /// unlock). Retried by `retryAfterUnlock()`; never overwritten.
        case locked
        /// Exists but undecodable — preserved verbatim, never written.
        case corrupt
        /// A newer app wrote this file — payload readable, file read-only.
        case newerSchema
    }

    private struct Box: Codable {
        var version: Int
        var payload: T
    }

    private let url: URL
    private let version: Int
    private let migrate: ((Int, inout T) -> Void)?
    private let legacyDecode: ((Data) -> T?)?
    private let initial: T
    private let directoryError: Error?
    private let lock = NSLock()
    private var cached: T?

    private var _lastError: Error?
    private var _state: State = .missing

    /// Last persistence error, for surfacing in UI.
    var lastError: Error? {
        lock.lock()
        defer { lock.unlock() }
        return _lastError
    }

    /// Why the store is refusing writes (`.missing`/`.ready` = fine).
    var state: State {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    /// `legacyDecode` is a last-resort reader: when both the versioned
    /// box and a bare payload fail to decode strictly, it gets the raw
    /// file bytes and may return a payload rebuilt with defaults —
    /// used so a settings file written before a field existed never
    /// becomes unreadable.
    init(_ name: String,
         initial: T,
         version: Int = 1,
         directory: URL? = nil,
         legacyDecode: ((Data) -> T?)? = nil,
         migrate: ((Int, inout T) -> Void)? = nil) {
        self.initial = initial
        self.version = version
        self.migrate = migrate
        self.legacyDecode = legacyDecode
        let dir = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            directoryError = nil
        } catch {
            // NOT swallowed — load()/save() surface this via lastError
            // and every save refuses to pretend it worked.
            directoryError = error
        }
        url = dir.appendingPathComponent("\(name).json")
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: url.path
                )
            } catch {
                // Hardening only — every save already writes with
                // .completeFileProtection, so a miss here is harmless.
            }
        }
    }

    var writable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _state == .missing || _state == .ready
    }

    func load() -> T {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            // No file yet — a fresh install, fully writable. A failed
            // directory creation still reaches the caller via lastError.
            _state = .missing
            _lastError = directoryError
            return initial
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
            // Locked (pre-first-unlock): recoverable — see retryAfterUnlock.
            _state = .locked
            _lastError = error
            return initial
        } catch {
            // Unreadable for any other reason — treat as corrupt.
            _state = .corrupt
            _lastError = error
            return initial
        }

        do {
            if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let storedVersion = object["version"] as? Int, storedVersion > version {
                _state = .newerSchema
                if let box = try? JSONDecoder().decode(Box.self, from: data) {
                    cached = box.payload
                    return box.payload
                }
                _lastError = NSError(domain: "Terminal.Storage", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "This data needs a newer version of Terminal"])
                return initial
            }
        } catch {
            // Strict decoding below reports malformed data consistently.
        }
        do {
            var box = try JSONDecoder().decode(Box.self, from: data)
            if box.version > version {
                // A newer app wrote this — expose the payload but never
                // clobber a schema we don't understand.
                _state = .newerSchema
                cached = box.payload
                return box.payload
            }
            if box.version < version {
                migrate?(box.version, &box.payload)
            }
            cached = box.payload
            _state = .ready
            _lastError = nil
            return box.payload
        } catch {
            let strictError = error
            // Legacy unversioned payload — the strict error stays the
            // one we report if everything below also fails.
            let legacy: T?
            do {
                legacy = try JSONDecoder().decode(T.self, from: data)
            } catch {
                legacy = nil
            }
            if let value = legacy {
                cached = value
                _state = .ready
                _lastError = nil
                return value
            }
            // Tolerant decode: an older schema may simply lack fields
            // added since — take their defaults instead of locking.
            if let value = legacyDecode?(data) {
                cached = value
                _state = .ready
                _lastError = nil
                return value
            }
            // Genuinely unreadable — never overwrite the user's data.
            _state = .corrupt
            _lastError = strictError
            return initial
        }
    }

    /// true only when the bytes actually hit disk. The in-memory cache
    /// is published AFTER a successful write — a failed save can no
    /// longer masquerade as the stored value.
    @discardableResult
    func save(_ value: T) -> Bool {
        // A caller may save before explicitly loading. Establish schema
        // and corruption guards before allowing that first write.
        _ = load()
        lock.lock()
        defer { lock.unlock() }
        if let directoryError {
            _lastError = directoryError
            return false
        }
        guard _state == .missing || _state == .ready else { return false }
        do {
            let data = try JSONEncoder().encode(Box(version: version, payload: value))
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            cached = value
            _state = .ready
            _lastError = nil
            return true
        } catch {
            // A failed write does NOT change state — it may be transient
            // (full disk, transient perms), and the cache stays honest
            // because it was never touched.
            _lastError = error
            return false
        }
    }

    /// Re-runs `load()` ONLY when the last failure was a data-protection
    /// lock — call from `protectedDataDidBecomeAvailable`. Corrupt and
    /// newer-schema states are deliberately untouched: recovering those
    /// is a user decision, not an automatic one. Returns true when a
    /// locked store actually recovered.
    @discardableResult
    func retryAfterUnlock() -> Bool {
        lock.lock()
        let isLocked = (_state == .locked)
        lock.unlock()
        guard isLocked else { return false }
        _ = load()
        return state != .locked
    }

    /// Raw bytes of a file we refuse to touch (corrupt or newer-schema)
    /// — enough for a recovery/export path that never overwrites it.
    func unrecoverableFileContents() -> Data? {
        lock.lock()
        let blocked = (_state == .corrupt || _state == .newerSchema)
        lock.unlock()
        guard blocked else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            return nil
        }
    }

    /// Explicit recovery preserves the original before writing defaults.
    @discardableResult
    func resetPreservingBackup() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        do {
            let original = try Data(contentsOf: url)
            let backup = url.deletingPathExtension()
                .appendingPathExtension("recovery-\(UUID().uuidString).json")
            try original.write(to: backup, options: [.atomic, .completeFileProtection])
            let replacement = try JSONEncoder().encode(Box(version: version, payload: initial))
            try replacement.write(to: url, options: [.atomic, .completeFileProtection])
            cached = initial
            _state = .ready
            _lastError = nil
            return true
        } catch {
            _lastError = error
            return false
        }
    }
}

