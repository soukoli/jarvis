import Foundation

/// How the caller wants the language handled for one chunk.
public enum LanguageHint: Sendable, Equatable {
    /// Let the engine detect among all languages it knows.
    case auto
    /// Detect, but only accept one of these ISO 639-1 codes (e.g. ["cs", "en"]).
    case autoAmong([String])
    /// Force one language.
    case fixed(String)
}

/// Result of transcribing one audio chunk.
public struct ChunkResult: Sendable, Equatable {
    public var text: String
    /// ISO 639-1 code the engine used or detected, if known.
    public var language: String?
    public var avgLogProb: Float?
    public var noSpeechProb: Float?
    public var compressionRatio: Float?
    public var timings: ChunkTimings

    public init(
        text: String,
        language: String? = nil,
        avgLogProb: Float? = nil,
        noSpeechProb: Float? = nil,
        compressionRatio: Float? = nil,
        timings: ChunkTimings = ChunkTimings()
    ) {
        self.text = text
        self.language = language
        self.avgLogProb = avgLogProb
        self.noSpeechProb = noSpeechProb
        self.compressionRatio = compressionRatio
        self.timings = timings
    }
}

public struct ChunkTimings: Sendable, Equatable {
    public var audioSeconds: Double = 0
    public var languageDetectionSeconds: Double = 0
    public var decodeSeconds: Double = 0
    public var totalSeconds: Double = 0

    public init() {}

    /// Real-time factor: wall-clock seconds per second of audio (lower is faster).
    public var realTimeFactor: Double { audioSeconds > 0 ? totalSeconds / audioSeconds : 0 }
}

/// One language-probability pair from a detection pass.
public struct LanguageProbability: Sendable, Equatable {
    public var code: String
    public var probability: Float
    public init(code: String, probability: Float) {
        self.code = code
        self.probability = probability
    }
}

/// A speech-to-text engine that transcribes one 16 kHz mono Float32 chunk at a time.
public protocol Transcriber: Sendable {
    /// Human-readable engine and model identifier for logs and the About box.
    var identifier: String { get }

    /// Load models (downloading if needed) and run any warm-up inference.
    func warmUp() async throws

    /// Detect the language of `samples`. Returns probabilities sorted descending.
    func detectLanguage(_ samples: [Float]) async throws -> [LanguageProbability]

    /// Transcribe `samples` (16 kHz mono, -1...1) with the given language hint.
    func transcribe(_ samples: [Float], hint: LanguageHint, prompt: String?) async throws -> ChunkResult

    /// Release models to free memory.
    func unload() async
}

public enum TranscriberError: Error, Sendable, CustomStringConvertible {
    case modelNotLoaded
    case languageNotSupported(String)
    case engineFailure(String)

    public var description: String {
        switch self {
        case .modelNotLoaded: return "Model is not loaded"
        case .languageNotSupported(let code): return "Language not supported: \(code)"
        case .engineFailure(let message): return "Engine failure: \(message)"
        }
    }
}
