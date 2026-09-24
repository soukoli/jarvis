import FluidAudio
import Foundation

/// One pause-delimited piece of speech, ready for transcription.
public struct SpeechChunk: Sendable {
    public var index: Int
    public var samples: [Float]
    public var duration: Double { Double(samples.count) / 16_000 }
}

/// Silero VAD (FluidAudio) driving the Python app's chunking rules: a chunk closes after
/// `minSilence` of quiet, chunks shorter than `minSpeech` are dropped, and a chunk is force-closed
/// at `maxSpeech` so it stays inside Whisper's 30 s window.
///
/// The model works on 4096-sample blocks (256 ms). Audio is kept in a session buffer and chunks are
/// cut by the sample indices FluidAudio reports for speech start/end, with a little padding so the
/// first consonant is not clipped.
public actor VADChunker {
    public struct Config: Sendable {
        public var threshold: Float = 0.5
        public var minSpeech: TimeInterval = 0.25
        public var minSilence: TimeInterval = 0.6
        public var maxSpeech: TimeInterval = 14
        public var padding: TimeInterval = 0.15
        public init() {}
    }

    private static let block = VadManager.chunkSize  // 4096
    private let vad: VadManager
    private let config: Config
    private let segmentation: VadSegmentationConfig

    private var state: VadStreamState
    private var pending: [Float] = []  // samples not yet forming a full block
    private var buffer: [Float] = []  // session audio from `base` onwards
    private var base = 0  // absolute index of buffer[0]
    private var speechStart: Int?  // absolute index where current speech began
    private var nextIndex = 0

    public init(vad: VadManager, config: Config = Config()) {
        self.vad = vad
        self.config = config
        var seg = VadSegmentationConfig()
        seg.minSpeechDuration = config.minSpeech
        seg.minSilenceDuration = config.minSilence
        seg.maxSpeechDuration = config.maxSpeech
        seg.speechPadding = 0  // we pad ourselves when cutting
        self.segmentation = seg
        self.state = VadStreamState.initial()
    }

    /// Load the Silero model (downloads ~8 MB on first use) and build a chunker.
    public static func make(config: Config = Config()) async throws -> VADChunker {
        let vad = try await VadManager(config: VadConfig(defaultThreshold: config.threshold))
        return VADChunker(vad: vad, config: config)
    }

    /// Feed microphone samples. Returns chunks that closed during this call.
    public func push(_ samples: [Float]) async throws -> [SpeechChunk] {
        pending.append(contentsOf: samples)
        var closed: [SpeechChunk] = []
        while pending.count >= Self.block {
            let blockSamples = Array(pending.prefix(Self.block))
            pending.removeFirst(Self.block)
            let blockStart = base + buffer.count
            buffer.append(contentsOf: blockSamples)

            let result = try await vad.processStreamingChunk(blockSamples, state: state, config: segmentation)
            state = result.state
            guard let event = result.event else { continue }
            switch event.kind {
            case .speechStart:
                speechStart = max(0, event.sampleIndex - paddingSamples)
                _ = blockStart
            case .speechEnd:
                if let chunk = cut(endingAt: event.sampleIndex + paddingSamples) { closed.append(chunk) }
                speechStart = nil
                trim()
            }
        }
        if speechStart == nil { trim() }
        return closed
    }

    /// End of recording: return whatever speech is open, even if the pause never came.
    public func flush() -> SpeechChunk? {
        // Include partial block audio so the last word is not lost.
        buffer.append(contentsOf: pending)
        pending.removeAll()
        defer { reset() }
        if speechStart != nil {
            return cut(endingAt: base + buffer.count)
        }
        // Speech may have started inside the last, not yet processed block: keep the tail if it is
        // long enough to be a word. The transcriber's no-speech check drops it if it is noise.
        let tail = buffer.suffix(Self.block + pending.count)
        if Double(tail.count) / 16_000 >= config.minSpeech, tail.contains(where: { abs($0) > 0.01 }) {
            let chunk = SpeechChunk(index: nextIndex, samples: Array(tail))
            nextIndex += 1
            return chunk
        }
        return nil
    }

    public func reset() {
        state = VadStreamState.initial()
        pending.removeAll()
        buffer.removeAll()
        base = 0
        speechStart = nil
        nextIndex = 0
    }

    // MARK: - Helpers

    private var paddingSamples: Int { Int(config.padding * 16_000) }

    private func cut(endingAt absoluteEnd: Int) -> SpeechChunk? {
        guard let start = speechStart else { return nil }
        let lo = max(start - base, 0)
        let hi = min(absoluteEnd - base, buffer.count)
        guard hi > lo else { return nil }
        let samples = Array(buffer[lo..<hi])
        guard Double(samples.count) / 16_000 >= config.minSpeech else { return nil }
        let chunk = SpeechChunk(index: nextIndex, samples: samples)
        nextIndex += 1
        return chunk
    }

    /// Drop audio that can no longer be part of a chunk, keeping one padding's worth for the next
    /// speech start.
    private func trim() {
        let keepFrom: Int
        if let start = speechStart {
            keepFrom = max(start - paddingSamples - base, 0)
        } else {
            keepFrom = max(buffer.count - paddingSamples - Self.block, 0)
        }
        guard keepFrom > 0 else { return }
        buffer.removeFirst(keepFrom)
        base += keepFrom
    }
}
