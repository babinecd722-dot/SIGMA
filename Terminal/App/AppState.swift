import Foundation
import SwiftUI
import Combine

/// Root application state: stores, session engine, keep-alive, app lock.
@MainActor
final class AppState: ObservableObject {
    let profiles = ProfilesStore()
    let keys = KeysStore()
    let knownHosts = KnownHostsStore()
    let snippets = SnippetsStore()
    let settings = SettingsStore()
    let keepAlive = KeepAliveEngine()

    private(set) lazy var engine = SessionEngine(
        profiles: profiles,
        keys: keys,
        knownHosts: knownHosts,
        settings: settings
    )

    @Published var locked = false
    private var unlocking = false
    private var lockGeneration = 0
    private var settingsObserver: AnyCancellable?
    private var previousRequiresUnlock = false

    init() {
        if settings.requiresUnlock {
            locked = true
        }
        previousRequiresUnlock = settings.requiresUnlock
        settingsObserver = settings.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let required = self.settings.requiresUnlock
                if required && !self.previousRequiresUnlock { self.lock() }
                self.previousRequiresUnlock = required
            }
        }
        Haptics.setEnabled(settings.settings.haptics)
        keepAlive.setEnabled(settings.settings.keepAlive)
        FileStaging.purgeKeyExportFolders(in: FileManager.default.temporaryDirectory)
        // A locked or corrupt keys file loads as an empty list. Sweeping
        // then would delete every private key in the Keychain.
        if !keys.storageBlocked {
            keys.removeOrphanedSecrets()
        }
    }

    /// Backgrounding re-arms the lock when the policy is on — the app
    /// must be locked again after every return, not only at launch.
    func lock() {
        guard settings.requiresUnlock else { return }
        lockGeneration += 1
        locked = true
    }

    /// Single evaluation at a time — a cancelled prompt followed by a
    /// retry must never stack two Face ID sheets.
    func unlock() async {
        guard locked, !unlocking else { return }
        unlocking = true
        let generation = lockGeneration
        defer { unlocking = false }
        if await BiometricGate.evaluate(String(localized: "Unlock Terminal")), generation == lockGeneration {
            locked = false
        }
    }
}
