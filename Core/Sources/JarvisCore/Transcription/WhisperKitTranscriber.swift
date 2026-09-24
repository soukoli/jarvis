import Foundation
import WhisperKit

/// `Transcriber` backed by WhisperKit (CoreML / Apple Neural Engine).
///
/// One instance owns one `WhisperKit` object. Calls are serialized by the actor, which is what we
/// want: the ANE does not benefit from parallel decodes and memory stays flat.
public actor WhisperKitTranscriber: Transcriber {
    public struct Options: Sendable {
        public var model: WhisperModel = .default
        public var downloadBase: URL = WhisperModel.defaultDownloadBase
        /// Already-downloaded model folder. When set, no network access happens.
        public var modelFolder: URL?
        /// Run CoreML specialization at load (slower first load, lower peak memory).
        public var prewarm: Bool = true
        public var verbose: Bool = false
        /// Mirrors the Python app: no_speech_threshold 0.6, compression_ratio_threshold 2.4,
        /// logprob -1.0, no context carry-over between chunks.
        public var noSpeechThreshold: Float = 0.6
        public var compressionRatioThreshold: Float = 2.4
        public var logProbThreshold: Float = -1.0
        public var temperatureFallbackCount: Int = 5
        public init() {}
    }

    public nonisolated let identifier: String
    private let options: Options
    private var whisperKit: WhisperKit?
    public private(set) var loadTiming: (download: Double, load: Double, warmUp: Double) = (0, 0, 0)

    public init(options: Options = Options()) {
        self.options = options
        self.identifier = "WhisperKit/\(options.model.variant)"
    }

    // MARK: Transcriber

    public func warmUp() async throws {
        if whisperKit != nil { return }
        let t0 = Date()
        var config = WhisperKitConfig(
            model: options.model.variant,
            downloadBase: options.downloadBase,
            modelFolder: options.modelFolder?.path,
            verbose: options.verbose,
            logLevel: options.verbose ? .debug : .error,
            prewarm: options.prewarm,
            load: true,
            download: options.modelFolder == nil
        )
        config.computeOptions = ModelComputeOptions()
        let kit = try await WhisperKit(config)
        let t1 = Date()
        // A short silent decode forces the remaining lazy initialization so the first real
        // chunk does not pay for it.
        _ = try await kit.transcribe(
            audioArray: [Float](repeating: 0, count: 16_000), decodeOptions: baseDecodingOptions())
        let t2 = Date()
        whisperKit = kit
        loadTiming = (0, t1.timeIntervalSince(t0), t2.timeIntervalSince(t1))
    }

    public func detectLanguage(_ samples: [Float]) async throws -> [LanguageProbability] {
        let kit = try loadedKit()
        let (_, probs) = try await kit.detectLangauge(audioArray: samples)
        return
            probs
            .map { LanguageProbability(code: $0.key, probability: $0.value) }
            .sorted { $0.probability > $1.probability }
    }

    public func transcribe(_ samples: [Float], hint: LanguageHint, prompt: String?) async throws -> ChunkResult {
        let kit = try loadedKit()
        let started = Date()
        var timings = ChunkTimings()
        timings.audioSeconds = Double(samples.count) / 16_000

        var decode = baseDecodingOptions()
        switch hint {
        case .auto:
            decode.language = nil
            decode.detectLanguage = true
        case .fixed(let code):
            decode.language = code
            decode.detectLanguage = false
        case .autoAmong(let allowed):
            let t = Date()
            let probs = try await detectLanguage(samples)
            timings.languageDetectionSeconds = Date().timeIntervalSince(t)
            let allowedSet = Set(allowed)
            let pick = probs.first { allowedSet.contains($0.code) } ?? probs.first
            decode.language = pick?.code
            decode.detectLanguage = pick == nil
        }
        if let prompt, !prompt.isEmpty, let tokenizer = kit.tokenizer {
            decode.promptTokens = tokenizer.encode(text: " " + prompt).filter {
                $0 < tokenizer.specialTokens.specialTokenBegin
            }
            decode.usePrefillPrompt = true
        }

        let t = Date()
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: decode)
        timings.decodeSeconds = Date().timeIntervalSince(t)
        timings.totalSeconds = Date().timeIntervalSince(started)

        let segments = results.flatMap(\.segments)
        // Standard Whisper rule (also what mlx-whisper applies): a segment is silence only when the
        // no-speech probability is high AND the decoded text is itself improbable. Filtering on
        // noSpeechProb alone throws away quiet but real speech.
        let kept = segments.filter {
            !($0.noSpeechProb > options.noSpeechThreshold && $0.avgLogprob < options.logProbThreshold)
        }
        let text = kept.map { $0.text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let language = results.first?.language ?? decode.language

        if text.isEmpty, !segments.isEmpty {
            // Segments without text: log decoder statistics (never the text itself).
            let detail = segments.prefix(3).map {
                "tokens=\($0.tokens.count) logprob=\(String(format: "%.2f", $0.avgLogprob)) cr=\(String(format: "%.2f", $0.compressionRatio)) t=\($0.temperature) chars=\($0.text.count)"
            }.joined(separator: "; ")
            Log.pipeline.notice(
                "empty text from \(segments.count, privacy: .public) segments [lang \(language ?? "?", privacy: .public), hint \(String(describing: hint), privacy: .public), prompt \(prompt != nil, privacy: .public)]: \(detail, privacy: .public)"
            )
        }

        return ChunkResult(
            text: text,
            language: language,
            avgLogProb: kept.map(\.avgLogprob).average,
            noSpeechProb: segments.map(\.noSpeechProb).average,
            compressionRatio: kept.map(\.compressionRatio).average,
            timings: timings
        )
    }

    public func unload() async {
        await whisperKit?.unloadModels()
        whisperKit = nil
    }

    // MARK: Helpers

    private func loadedKit() throws -> WhisperKit {
        guard let whisperKit else { throw TranscriberError.modelNotLoaded }
        return whisperKit
    }

    private func baseDecodingOptions() -> DecodingOptions {
        var d = DecodingOptions()
        d.task = .transcribe
        d.usePrefillPrompt = true
        d.skipSpecialTokens = true
        d.withoutTimestamps = true
        d.wordTimestamps = false
        d.temperatureFallbackCount = options.temperatureFallbackCount
        d.compressionRatioThreshold = options.compressionRatioThreshold
        d.logProbThreshold = options.logProbThreshold
        d.noSpeechThreshold = options.noSpeechThreshold
        d.chunkingStrategy = ChunkingStrategy.none
        return d
    }
}

extension Array where Element == Float {
    var average: Float? { isEmpty ? nil : reduce(0, +) / Float(count) }
}
