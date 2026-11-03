import SwiftUI
import UniformTypeIdentifiers

struct StorageRecoveryView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: SettingsStore
    @State private var document: RecoveryDocument?
    @State private var filename = "recovery"
    @State private var exporting = false
    @State private var confirmReset = false
    @State private var failed = false

    private struct Copy: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let data: Data
    }

    private var copies: [Copy] {
        [
            appState.profiles.unrecoverableData.map { Copy(id: "servers", title: "Servers", data: $0) },
            appState.keys.unrecoverableData.map { Copy(id: "keys", title: "Keys", data: $0) },
            appState.knownHosts.unrecoverableData.map { Copy(id: "identities", title: "Server identities", data: $0) },
            appState.snippets.unrecoverableData.map { Copy(id: "snippets", title: "Snippets", data: $0) },
            settings.unrecoverableData.map { Copy(id: "settings", title: "Settings", data: $0) }
        ].compactMap { $0 }
    }

    var body: some View {
        Form {
            Section {
                Text("Your saved data needs attention. Export a copy before making changes.")
                    .foregroundStyle(.secondary)
                ForEach(copies) { copy in
                    Button {
                        filename = copy.id + "-recovery"
                        document = RecoveryDocument(data: copy.data)
                        exporting = true
                    } label: {
                        Label(copy.title, systemImage: "square.and.arrow.up")
                    }
                }
            }
            if settings.storageBlocked {
                Section {
                    Button("Reset Settings", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Your servers and keys will be kept.")
                }
            }
        }
        .navigationTitle("Recover Data")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $exporting, document: document,
                      contentType: .json, defaultFilename: filename) { result in
            if case .failure = result { failed = true }
        }
        .confirmationDialog("Reset settings?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset Settings", role: .destructive) {
                if !settings.resetPreservingBackup() { failed = true }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A copy of your saved settings will be kept.")
        }
        .alert("Couldn't complete recovery", isPresented: $failed) {
            Button("OK") {}
        }
    }
}

private struct RecoveryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .data] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
