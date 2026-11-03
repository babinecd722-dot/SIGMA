import SwiftUI

/// Settings sheet. Grouped form on a dark surface, accent chips
/// for glyphs — no explanatory copy anywhere.
struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var keepAlive: KeepAliveEngine
    /// A refused write reverts the control silently — the alert is how
    /// the user learns the setting didn't stick.
    @State private var saveFailed = false
    @State private var fontSizeDraft = 13.0
    @State private var shellDraft = ""
    @FocusState private var shellFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState

    private var needsRecovery: Bool {
        settings.storageBlocked || appState.profiles.storageBlocked || appState.keys.storageBlocked
            || appState.knownHosts.storageBlocked || appState.snippets.storageBlocked
    }

    private func saveShell() {
        if settings.settings.shellOverride != shellDraft {
            settings.settings.shellOverride = shellDraft
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if needsRecovery {
                    Section {
                        NavigationLink {
                            StorageRecoveryView()
                        } label: {
                            Label("Recover Data", systemImage: "exclamationmark.triangle")
                        }
                    }
                }
                Section {
                    Picker(selection: $settings.settings.appearance) {
                        Text("Dark").tag(AppSettings.Appearance.dark)
                        Text("Light").tag(AppSettings.Appearance.light)
                        Text("System").tag(AppSettings.Appearance.system)
                    } label: {
                        rowLabel("Appearance", icon: "circle.lefthalf.filled")
                    }

                    .pickerStyle(.menu)
                    .accessibilityIdentifier("appearancePicker")

                    NavigationLink {
                        ThemePickerView()
                    } label: {
                        HStack {
                            rowLabel("Theme", icon: "paintpalette")
                            Spacer()
                            Text(settings.settings.themeID == "auto" ? String(localized: "Auto") : TerminalTheme.theme(id: settings.settings.themeID).displayName)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        Text("Aa")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Slider(value: $fontSizeDraft, in: 10...18, step: 1) { editing in
                            if !editing { settings.settings.fontSize = fontSizeDraft }
                        }
                        .accessibilityLabel("Font size")
                        .accessibilityValue(Text("\(Int(fontSizeDraft))"))
                        Text("Aa")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .onChange(of: fontSizeDraft) { _, _ in
                        Haptics.select()
                    }
                }

                Section {
                    Toggle(isOn: $settings.settings.keepAlive) {
                        rowLabel("Keep-alive audio", icon: "antenna.radiowaves.left.and.right")
                    }
                    .onChange(of: settings.settings.keepAlive) { _, on in
                        keepAlive.setEnabled(on)
                    }

                    Toggle(isOn: $settings.settings.remoteClipboard) {
                        rowLabel("Remote clipboard", icon: "doc.on.clipboard")
                    }

                    if BiometricGate.available {
                        Toggle(isOn: $settings.settings.requireBiometry) {
                            rowLabel("Passcode or biometrics", icon: "faceid")
                        }
                    }

                    Toggle(isOn: $settings.settings.haptics) {
                        rowLabel("Haptics", icon: "iphone.radiowaves.left.and.right")
                    }
                    .onChange(of: settings.settings.haptics) { _, on in
                        Haptics.setEnabled(on)
                    }

                    Toggle(isOn: $settings.settings.autoReconnect) {
                        rowLabel("Auto-reconnect", icon: "arrow.triangle.2.circlepath")
                    }

                    Toggle(isOn: $settings.settings.autoTmux) {
                        rowLabel("Resume sessions", icon: "clock.arrow.circlepath")
                    }

                    Toggle(isOn: $settings.settings.showKeyboardBar) {
                        rowLabel("Extra keys", icon: "keyboard")
                    }

                    LabeledContent {
                        TextField("Default", text: $shellDraft)
                            .focused($shellFocused)
                            .submitLabel(.done)
                            .onSubmit { saveShell() }
                            .onChange(of: shellFocused) { _, focused in
                                if !focused { saveShell() }
                            }
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } label: {
                        rowLabel("Shell", icon: "terminal")
                    }
                } footer: {
                    // Both switches gate tmux — say so at the only
                    // place the global one is visible.
                    Text("Resume sessions also needs each server's own switch.")
                }

                Section {
                    NavigationLink {
                        KeysListView()
                    } label: {
                        rowLabel("Keys", icon: "key.fill")
                    }

                    NavigationLink {
                        SnippetsListView()
                    } label: {
                        rowLabel("Snippets", icon: "chevron.left.forwardslash.chevron.right")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.terminalSurface.ignoresSafeArea())
            .tint(.terminalAccent)
            .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fontSizeDraft = settings.settings.fontSize
            shellDraft = settings.settings.shellOverride
        }
        .onDisappear { saveShell() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                saveShell()
                if settings.settings.fontSize != fontSizeDraft {
                    settings.settings.fontSize = fontSizeDraft
                }
            }
        }
        .onChange(of: settings.storageError != nil) { _, hasError in
            if hasError {
                saveFailed = true
                Haptics.failed()
            }
        }
        .alert(String(localized: "Couldn't save settings"), isPresented: $saveFailed) {
            Button("OK") {}
        }
        }
    }

    /// Settings-style row: accent rounded square with a white glyph + title.
    /// LocalizedStringKey — a String argument would render verbatim.
    private func rowLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    Color.terminalAccent,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
    }
}
