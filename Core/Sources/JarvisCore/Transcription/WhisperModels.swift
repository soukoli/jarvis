import Foundation

/// Catalog of WhisperKit CoreML variants Jarvis offers. Keys mirror the Python app's
/// `AVAILABLE_MODELS` so settings migrate 1:1.
public struct WhisperModel: Sendable, Identifiable, Equatable {
    public var id: String  // Jarvis key, e.g. "large-v3-turbo"
    public var variant: String  // WhisperKit variant folder name in argmaxinc/whisperkit-coreml
    public var display: String
    public var approxSizeMB: Int
    public var note: String

    public static let catalog: [WhisperModel] = [
        WhisperModel(
            id: "large-v3-turbo",
            variant: "openai_whisper-large-v3-v20240930_turbo",
            display: "Large v3 Turbo (fp16)",
            approxSizeMB: 1640,
            note: "Best Czech accuracy; default."
        ),
        WhisperModel(
            id: "large-v3-turbo-q4",
            variant: "openai_whisper-large-v3-v20240930_turbo_632MB",
            display: "Large v3 Turbo (compressed)",
            approxSizeMB: 646,
            note: "Same model, ~2.5x smaller; faster first load."
        ),
        WhisperModel(
            id: "small",
            variant: "openai_whisper-small_216MB",
            display: "Small (compressed)",
            approxSizeMB: 217,
            note: "Fastest; noticeably worse on Czech."
        ),
    ]

    public static let `default` = catalog[0]

    public static func byKey(_ key: String) -> WhisperModel? {
        catalog.first { $0.id == key } ?? catalog.first { $0.variant == key }
    }

    /// Where Jarvis keeps downloaded models: ~/Library/Application Support/Jarvis/Models
    public static var defaultDownloadBase: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Jarvis/Models", isDirectory: true)
    }
}
