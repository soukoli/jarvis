import Foundation
import Observation

/// Languages offered in the menu (same list as the Python app).
public struct Language: Sendable, Identifiable, Hashable {
    public var id: String  // ISO 639-1, or "auto"
    public var name: String
    public var flag: String

    public static let auto = Language(id: "auto", name: "Auto-detect", flag: "🌐")
    public static let all: [Language] = [
        auto,
        Language(id: "cs", name: "Czech / Čeština", flag: "🇨🇿"),
        Language(id: "en", name: "English", flag: "🇬🇧"),
        Language(id: "sk", name: "Slovak / Slovenčina", flag: "🇸🇰"),
        Language(id: "de", name: "German / Deutsch", flag: "🇩🇪"),
        Language(id: "es", name: "Spanish / Español", flag: "🇪🇸"),
        Language(id: "fr", name: "French / Français", flag: "🇫🇷"),
        Language(id: "it", name: "Italian / Italiano", flag: "🇮🇹"),
        Language(id: "pl", name: "Polish / Polski", flag: "🇵🇱"),
        Language(id: "pt", name: "Portuguese / Português", flag: "🇵🇹"),
        Language(id: "ru", name: "Russian / Русский", flag: "🇷🇺"),
        Language(id: "uk", name: "Ukrainian / Українська", flag: "🇺🇦"),
    ]
    public static func byID(_ id: String) -> Language { all.first { $0.id == id } ?? auto }
}

public enum InsertionMode: String, Sendable, CaseIterable, Identifiable {
    case insert  // at the caret, clipboard restored
    case insertAndCopy  // at the caret, and leave it on the clipboard
    case copyOnly  // Python behavior
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .insert: return "Insert at cursor"
        case .insertAndCopy: return "Insert at cursor and copy"
        case .copyOnly: return "Copy to clipboard only"
        }
    }
}

/// All user settings, persisted in `UserDefaults`, observable by SwiftUI.
/// Migrates once from the Python app's `~/.jarvis_config.json`.
@MainActor
@Observable
public final class SettingsStore {
    public static let shared = SettingsStore()

    private let defaults: UserDefaults

    public var language: String { didSet { defaults.set(language, forKey: "language") } }
    /// Languages allowed when auto-detecting; empty = any.
    public var preferredLanguages: [String] {
        didSet { defaults.set(preferredLanguages, forKey: "preferredLanguages") }
    }
    public var modelKey: String { didSet { defaults.set(modelKey, forKey: "modelKey") } }
    public var deviceUID: String? { didSet { defaults.set(deviceUID, forKey: "deviceUID") } }
    public var deviceName: String? { didSet { defaults.set(deviceName, forKey: "deviceName") } }
    /// When the system default input is a Bluetooth headset, record from the built-in mic instead.
    public var preferBuiltInMic: Bool { didSet { defaults.set(preferBuiltInMic, forKey: "preferBuiltInMic") } }
    public var completionSound: Bool { didSet { defaults.set(completionSound, forKey: "completionSound") } }
    public var startSound: Bool { didSet { defaults.set(startSound, forKey: "startSound") } }
    public var insertionMode: InsertionMode { didSet { defaults.set(insertionMode.rawValue, forKey: "insertionMode") } }
    public var glossary: String { didSet { defaults.set(glossary, forKey: "glossary") } }
    public var vadThreshold: Float { didSet { defaults.set(vadThreshold, forKey: "vadThreshold") } }
    public var minSpeechMs: Int { didSet { defaults.set(minSpeechMs, forKey: "minSpeechMs") } }
    public var minSilenceMs: Int { didSet { defaults.set(minSilenceMs, forKey: "minSilenceMs") } }
    public var hotkeyStart: Hotkey { didSet { save(hotkeyStart, key: "hotkeyStart") } }
    public var hotkeyStop: Hotkey { didSet { save(hotkeyStop, key: "hotkeyStop") } }
    public var hotkeyCancel: Hotkey { didSet { save(hotkeyCancel, key: "hotkeyCancel") } }
    public var hotkeyPushToTalk: Hotkey { didSet { save(hotkeyPushToTalk, key: "hotkeyPushToTalk") } }
    public var pushToTalkEnabled: Bool { didSet { defaults.set(pushToTalkEnabled, forKey: "pushToTalkEnabled") } }
    public var showPreview: Bool { didSet { defaults.set(showPreview, forKey: "showPreview") } }
    public var debugLogging: Bool { didSet { defaults.set(debugLogging, forKey: "debugLogging") } }
    public var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: "onboardingDone") } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = defaults.string(forKey: "language") ?? "auto"
        preferredLanguages = defaults.stringArray(forKey: "preferredLanguages") ?? []
        modelKey = defaults.string(forKey: "modelKey") ?? WhisperModel.default.id
        deviceUID = defaults.string(forKey: "deviceUID")
        deviceName = defaults.string(forKey: "deviceName")
        preferBuiltInMic = defaults.object(forKey: "preferBuiltInMic") as? Bool ?? false
        completionSound = defaults.object(forKey: "completionSound") as? Bool ?? true
        startSound = defaults.object(forKey: "startSound") as? Bool ?? true
        insertionMode = InsertionMode(rawValue: defaults.string(forKey: "insertionMode") ?? "") ?? .insert
        glossary = defaults.string(forKey: "glossary") ?? ""
        vadThreshold = defaults.object(forKey: "vadThreshold") as? Float ?? 0.5
        minSpeechMs = defaults.object(forKey: "minSpeechMs") as? Int ?? 250
        minSilenceMs = defaults.object(forKey: "minSilenceMs") as? Int ?? 600
        hotkeyStart = Self.load(defaults, key: "hotkeyStart") ?? .defaultStart
        hotkeyStop = Self.load(defaults, key: "hotkeyStop") ?? .defaultStop
        hotkeyCancel = Self.load(defaults, key: "hotkeyCancel") ?? .defaultCancel
        hotkeyPushToTalk = Self.load(defaults, key: "hotkeyPushToTalk") ?? .defaultPushToTalk
        pushToTalkEnabled = defaults.object(forKey: "pushToTalkEnabled") as? Bool ?? true
        showPreview = defaults.object(forKey: "showPreview") as? Bool ?? true
        debugLogging = defaults.bool(forKey: "debugLogging")
        onboardingDone = defaults.bool(forKey: "onboardingDone")

        if !defaults.bool(forKey: "migratedFromJSONv1") {
            migrateLegacyConfig()
            defaults.set(true, forKey: "migratedFromJSONv1")
        }
    }

    public var vadConfig: VADChunker.Config {
        var c = VADChunker.Config()
        c.threshold = vadThreshold
        c.minSpeech = Double(minSpeechMs) / 1000
        c.minSilence = Double(minSilenceMs) / 1000
        return c
    }

    public var languageHint: LanguageHint {
        if language != "auto" { return .fixed(language) }
        return preferredLanguages.isEmpty ? .auto : .autoAmong(preferredLanguages)
    }

    public var model: WhisperModel { WhisperModel.byKey(modelKey) ?? .default }

    // MARK: - Legacy migration

    /// Reads `~/.jarvis_config.json` (Python app) once. The file is left untouched.
    public func migrateLegacyConfig(
        at url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".jarvis_config.json")
    ) {
        guard let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        if let l = json["language"] as? String, Language.all.contains(where: { $0.id == l }) { language = l }
        if let m = json["model_size"] as? String, WhisperModel.byKey(m) != nil { modelKey = m }
        if let d = json["device_name"] as? String, !d.isEmpty { deviceName = d }
        if let s = json["completion_sound"] as? Bool { completionSound = s }
        if let h = json["hotkey_start"] as? String, let k = Hotkey.fromLegacyCharacter(h) { hotkeyStart = k }
        if let h = json["hotkey_stop"] as? String, let k = Hotkey.fromLegacyCharacter(h) { hotkeyStop = k }
        if let h = json["hotkey_cancel"] as? String, let k = Hotkey.fromLegacyCharacter(h) { hotkeyCancel = k }
        Log.app.info("migrated legacy config from \(url.path, privacy: .public)")
    }

    /// Restore every setting to its default. Models on disk are left alone.
    public func resetToDefaults() {
        language = "auto"
        preferredLanguages = []
        modelKey = WhisperModel.default.id
        deviceUID = nil
        deviceName = nil
        preferBuiltInMic = false
        completionSound = true
        startSound = true
        insertionMode = .insert
        glossary = ""
        vadThreshold = 0.5
        minSpeechMs = 250
        minSilenceMs = 600
        hotkeyStart = .defaultStart
        hotkeyStop = .defaultStop
        hotkeyCancel = .defaultCancel
        hotkeyPushToTalk = .defaultPushToTalk
        pushToTalkEnabled = true
        showPreview = true
        debugLogging = false
    }

    // MARK: - Helpers

    private func save(_ hotkey: Hotkey, key: String) {
        if let data = try? JSONEncoder().encode(hotkey) { defaults.set(data, forKey: key) }
    }

    private static func load(_ defaults: UserDefaults, key: String) -> Hotkey? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Hotkey.self, from: data)
    }
}
