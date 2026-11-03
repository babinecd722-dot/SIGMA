import Foundation

/// Every `AppSettings` field as an optional — a file written before a
/// field existed decodes cleanly and takes the current default for the
/// missing key instead of failing the whole payload.
private struct LegacyAppSettings: Decodable {
    var keepAlive: Bool?
    var requireBiometry: Bool?
    var autoTmux: Bool?
    var fontSize: Double?
    var themeID: String?
    var appearance: String?
    var haptics: Bool?
    var showKeyboardBar: Bool?
    var autoReconnect: Bool?
    var shellOverride: String?
    var remoteClipboard: Bool?

    func upgraded() -> AppSettings {
        var s = AppSettings()
        if let keepAlive { s.keepAlive = keepAlive }
        if let requireBiometry { s.requireBiometry = requireBiometry }
        if let autoTmux { s.autoTmux = autoTmux }
        if let fontSize { s.fontSize = fontSize }
        if let themeID { s.themeID = themeID }
        if let appearance, let value = AppSettings.Appearance(rawValue: appearance) {
            s.appearance = value
        }
        if let haptics { s.haptics = haptics }
        if let showKeyboardBar { s.showKeyboardBar = showKeyboardBar }
        if let autoReconnect { s.autoReconnect = autoReconnect }
        if let shellOverride { s.shellOverride = shellOverride }
        if let remoteClipboard { s.remoteClipboard = remoteClipboard }
        return s
    }
}

/// Versioned envelope whose payload is read tolerantly.
private struct LegacySettingsBox: Decodable {
    var version: Int
    var payload: LegacyAppSettings
}

enum SettingsCodec {
    static func decodeLegacy(_ data: Data) -> AppSettings? {
        let known: Set<String> = ["keepAlive", "requireBiometry", "autoTmux", "fontSize", "themeID",
            "appearance", "haptics", "showKeyboardBar", "autoReconnect", "shellOverride", "remoteClipboard"]
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let fields: [String: Any]
        let enveloped = object["version"] != nil || object["payload"] != nil
        if enveloped {
            guard let payload = object["payload"] as? [String: Any] else { return nil }
            fields = payload
        } else { fields = object }
        guard fields.contains(where: { known.contains($0.key) && !($0.value is NSNull) }) else { return nil }
        if enveloped {
            guard let box = try? JSONDecoder().decode(LegacySettingsBox.self, from: data),
                  box.version == 1 else { return nil }
            return box.payload.upgraded()
        }
        return (try? JSONDecoder().decode(LegacyAppSettings.self, from: data))?.upgraded()
    }
}
