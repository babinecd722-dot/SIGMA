import XCTest
@testable import Terminal

final class SettingsCodecTests: XCTestCase {
    func testLegacySettingsKeepSecurityPolicyAndDefaults() throws {
        let bytes = Data(#"{"version":1,"payload":{"requireBiometry":true,"haptics":false}}"#.utf8)
        let value = try XCTUnwrap(SettingsCodec.decodeLegacy(bytes))
        XCTAssertTrue(value.requireBiometry)
        XCTAssertFalse(value.haptics)
        XCTAssertTrue(value.autoReconnect)
    }

    func testArbitraryOrMalformedObjectsAreNotSettings() {
        for json in ["{}", #"{"unrelated":true}"#, #"{"requireBiometry":null}"#,
                     #"{"version":1}"#, #"{"version":99,"payload":{"haptics":false}}"#,
                     #"{"version":true,"payload":{"requireBiometry":true}}"#,
                     #"{"version":1,"payload":{"requireBiometry":"true"}}"#] {
            XCTAssertNil(SettingsCodec.decodeLegacy(Data(json.utf8)), json)
        }
    }

    func testNewerPartialSchemaCannotBeWrittenThroughTolerantDecoder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data(#"{"version":99,"payload":{"haptics":false}}"#.utf8)
        let url = directory.appendingPathComponent("settings.json")
        try bytes.write(to: url)
        let store = JSONStore("settings", initial: AppSettings(), directory: directory,
                              legacyDecode: SettingsCodec.decodeLegacy)
        _ = store.load()
        XCTAssertEqual(store.state, .newerSchema)
        XCTAssertFalse(store.save(AppSettings()))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    func testUnusableFontSizesHaveSafeBounds() {
        var settings = AppSettings()
        settings.fontSize = .infinity
        XCTAssertEqual(settings.sanitized.fontSize, 13)
        settings.fontSize = 1e50
        XCTAssertEqual(settings.sanitized.fontSize, 18)
        settings.fontSize = -100
        XCTAssertEqual(settings.sanitized.fontSize, 10)
    }

}
