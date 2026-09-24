import Carbon.HIToolbox
import Foundation
import Testing

@testable import JarvisCore

@Suite struct HotkeyTests {
    @Test func legacyCharactersMapToUSKeyCodes() {
        #expect(Hotkey.fromLegacyCharacter(";") == .defaultStart)
        #expect(Hotkey.fromLegacyCharacter("'") == .defaultStop)
        #expect(Hotkey.fromLegacyCharacter(".") == .defaultCancel)
        #expect(Hotkey.fromLegacyCharacter("r")?.keyCode == UInt32(kVK_ANSI_R))
        #expect(Hotkey.fromLegacyCharacter("§") == nil)
    }

    @Test func codableRoundTrip() throws {
        let h = Hotkey(keyCode: 12, modifiers: Hotkey.cmd | Hotkey.shift)
        let data = try JSONEncoder().encode(h)
        #expect(try JSONDecoder().decode(Hotkey.self, from: data) == h)
    }

    @Test func displayShowsModifiers() {
        let h = Hotkey(keyCode: UInt32(kVK_Space), modifiers: Hotkey.cmd | Hotkey.option)
        #expect(h.display == "⌥⌘Space")
    }
}

@Suite struct SettingsMigrationTests {
    @Test @MainActor func migratesLegacyJSON() throws {
        let suite = "JarvisTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "migratedFromJSONv1")  // block the automatic home-dir migration

        let json = """
            {"language": "cs", "model_size": "large-v3-turbo-q4", "device_name": "MacBook Pro Microphone",
             "completion_sound": false, "hotkey_start": "r", "hotkey_stop": "'", "hotkey_cancel": "."}
            """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "jarvis-legacy-\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = SettingsStore(defaults: defaults)
        store.migrateLegacyConfig(at: url)

        #expect(store.language == "cs")
        #expect(store.modelKey == "large-v3-turbo-q4")
        #expect(store.deviceName == "MacBook Pro Microphone")
        #expect(store.completionSound == false)
        #expect(store.hotkeyStart.keyCode == UInt32(kVK_ANSI_R))
        #expect(store.hotkeyStop == .defaultStop)
        #expect(defaults.string(forKey: "language") == "cs")  // persisted
    }

    @Test @MainActor func languageHintFollowsSettings() {
        let suite = "JarvisTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "migratedFromJSONv1")
        let store = SettingsStore(defaults: defaults)
        #expect(store.languageHint == .auto)
        store.preferredLanguages = ["cs", "en"]
        #expect(store.languageHint == .autoAmong(["cs", "en"]))
        store.language = "cs"
        #expect(store.languageHint == .fixed("cs"))
    }
}
