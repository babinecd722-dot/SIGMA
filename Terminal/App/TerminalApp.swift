import SwiftUI

@main
struct TerminalApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TerminalWindowView()
                .environmentObject(appState)
                .environmentObject(appState.profiles)
                .environmentObject(appState.keys)
                .environmentObject(appState.knownHosts)
                .environmentObject(appState.snippets)
                .environmentObject(appState.settings)
                .environmentObject(appState.engine)
                .environmentObject(appState.keepAlive)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                appState.keepAlive.setBackgrounded(true)
                PrivacyOverlay.shared.update(visible: true, locked: appState.locked, appState: appState)
                // Relock on every exit — not just the cold start. The
                // Face ID sheet itself sends .inactive, so locking on
                // .inactive would deadlock the unlock prompt.
                appState.lock()
            case .inactive:
                PrivacyOverlay.shared.update(visible: true, locked: appState.locked, appState: appState)
            case .active:
                appState.keepAlive.setBackgrounded(false)
                if appState.locked {
                    PrivacyOverlay.shared.update(visible: true, locked: true, appState: appState)
                    Task { await appState.unlock() }
                } else {
                    PrivacyOverlay.shared.update(visible: false, locked: false, appState: appState)
                }
            @unknown default:
                break
            }
        }
        .onChange(of: appState.locked) { _, locked in
            guard scenePhase == .active else { return }
            PrivacyOverlay.shared.update(visible: locked, locked: locked, appState: appState)
        }
    }

}

/// Observe the store that owns appearance directly. Observing AppState
/// does not subscribe to changes in its nested stores.
struct TerminalWindowView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        RootView().preferredColorScheme(settings.settings.appearance.colorScheme)
    }
}

extension AppSettings.Appearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}
