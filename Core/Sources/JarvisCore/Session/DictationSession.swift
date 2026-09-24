import Foundation

/// One recording: microphone -> VAD chunks -> sequential transcription -> ordered text.
///
/// `start()` begins capture; chunks are transcribed while the user is still speaking. `stop()`
/// flushes the open chunk immediately (no waiting for the silence timeout), waits for the queue
/// to drain and returns the assembled text. `cancel()` discards everything.
public actor DictationSession {
    public enum Event: Sendable {
        case partial(String)  // text so far
        case chunk(index: Int, text: String, audioSeconds: Double, decodeSeconds: Double)
        case silentInput
        case captureFailed(String)
    }

    public nonisolated let events: AsyncStream<Event>
    private let eventContinuation: AsyncStream<Event>.Continuation

    private let transcriber: any Transcriber
    private let chunker: VADChunker
    private let hint: LanguageHint
    private let prompt: String?
    private let capture: AudioCapture
    private let device: AudioInputDevice?

    private var assembler = TranscriptAssembler()
    private var captureTask: Task<Void, Never>?
    private var worker: Task<Void, Never>?
    private var queue: [SpeechChunk] = []
    private var cancelled = false
    private var started = false
    private var pendingCount = 0
    private let signpost = Log.signposter

    /// Input diagnostics for the UI and the CLI: how much audio arrived and how loud it was.
    public struct Stats: Sendable {
        public var samples = 0
        public var peak: Float = 0
        public var chunks = 0
        public var seconds: Double { Double(samples) / 16_000 }
    }
    public private(set) var stats = Stats()

    public init(
        transcriber: any Transcriber,
        chunker: VADChunker,
        hint: LanguageHint,
        prompt: String? = nil,
        device: AudioInputDevice? = nil,
        capture: AudioCapture = AudioCapture()
    ) {
        self.transcriber = transcriber
        self.chunker = chunker
        self.hint = hint
        self.prompt = prompt
        self.device = device
        self.capture = capture
        (events, eventContinuation) = AsyncStream<Event>.makeStream(bufferingPolicy: .unbounded)
    }

    // MARK: - Lifecycle

    public func start() async throws {
        precondition(!started, "session already started")
        started = true
        await chunker.reset()
        let stream = try capture.start(device: device)
        Log.pipeline.info("session started")
        captureTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .audio(let samples):
                    do {
                        await self.record(samples)
                        let closed = try await self.chunker.push(samples)
                        for chunk in closed { await self.enqueue(chunk) }
                    } catch {
                        Log.pipeline.error("VAD failed: \(String(describing: error), privacy: .public)")
                    }
                case .silentInput:
                    await self.emit(.silentInput)
                case .noInput(let deviceName):
                    await self.emit(
                        .captureFailed(
                            "No audio from \(deviceName). If it is a Bluetooth headset, pick the built-in microphone in Settings → Audio."
                        ))
                case .ended:
                    return
                }
            }
        }
    }

    /// Stop recording and return the final text. Empty string if nothing was recognized.
    public func stop() async -> String {
        let state = signpost.beginInterval("stopToText")
        capture.stop()
        await captureTask?.value
        captureTask = nil
        if cancelled { return "" }

        if let last = await chunker.flush() { enqueue(last) }
        await drainWorker()
        signpost.endInterval("stopToText", state)
        eventContinuation.finish()
        let text = assembler.text
        Log.pipeline.info(
            "session finished: \(self.assembler.acceptedChunkCount, privacy: .public) accepted of \(self.stats.chunks, privacy: .public) chunks, \(text.count, privacy: .public) chars; audio \(self.stats.seconds, format: .fixed(precision: 1), privacy: .public) s, peak \(self.stats.peak, format: .fixed(precision: 3), privacy: .public)"
        )
        return text
    }

    public func cancel() async {
        cancelled = true
        capture.stop()
        captureTask?.cancel()
        worker?.cancel()
        queue.removeAll()
        await chunker.reset()
        eventContinuation.finish()
        Log.pipeline.info("session cancelled")
    }

    public var isCancelled: Bool { cancelled }

    // MARK: - Transcription queue (sequential; one ANE)

    private func record(_ samples: [Float]) {
        stats.samples += samples.count
        var peak = stats.peak
        for s in samples where abs(s) > peak { peak = abs(s) }
        stats.peak = peak
    }

    private func enqueue(_ chunk: SpeechChunk) {
        guard !cancelled else { return }
        stats.chunks += 1
        queue.append(chunk)
        pendingCount += 1
        if worker == nil {
            worker = Task { [weak self] in await self?.drain() }
        }
    }

    private func drain() async {
        while !queue.isEmpty, !cancelled, !Task.isCancelled {
            let chunk = queue.removeFirst()
            let state = signpost.beginInterval("chunk")
            do {
                let result = try await transcriber.transcribe(chunk.samples, hint: hint, prompt: prompt)
                if !cancelled {
                    if let accepted = assembler.add(index: chunk.index, text: result.text) {
                        emit(
                            .chunk(
                                index: chunk.index, text: accepted, audioSeconds: chunk.duration,
                                decodeSeconds: result.timings.decodeSeconds))
                        emit(.partial(assembler.text))
                    } else {
                        Log.pipeline.info(
                            "chunk \(chunk.index, privacy: .public) dropped by filter (\(result.text.count, privacy: .public) chars, noSpeech \(result.noSpeechProb ?? -1, format: .fixed(precision: 2), privacy: .public))"
                        )
                    }
                }
            } catch {
                Log.pipeline.error(
                    "transcription failed for chunk \(chunk.index, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
            signpost.endInterval("chunk", state)
            pendingCount -= 1
        }
        worker = nil
    }

    /// Wait until every queued chunk has been transcribed. The actor is reentrant, so chunks may be
    /// enqueued while we await; `drain()` only exits with an empty queue and clears `worker`.
    private func drainWorker() async {
        while true {
            if let w = worker {
                await w.value
                continue
            }
            if queue.isEmpty { return }
            worker = Task { [weak self] in await self?.drain() }
        }
    }

    private func emit(_ event: Event) {
        eventContinuation.yield(event)
    }
}
