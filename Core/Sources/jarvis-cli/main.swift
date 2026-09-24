import ArgumentParser
import Foundation
import JarvisCore

@main
struct JarvisCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "jarvis-cli",
        abstract: "Jarvis native spike tools: transcribe, detect language, benchmark.",
        subcommands: [Transcribe.self, Detect.self, Bench.self, Models.self, Inject.self, Doctor.self, Record.self]
    )
}

// MARK: - record (end-to-end pipeline without the GUI)

struct Record: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Record from the microphone for N seconds through VAD + Whisper and print the text.")

    @Option(name: .long, help: "Seconds to record.") var seconds: Int = 8
    @OptionGroup var engine: EngineOptions
    @OptionGroup var lang: LanguageOptions
    @Option(name: .long, help: "Input device name (substring match). Default: system default.") var device: String?
    @Flag(name: .long, help: "Insert the result at the cursor after recording (3 s countdown first).") var insert =
        false

    func run() async throws {
        let transcriber = try engine.makeTranscriber()
        FileHandle.standardError.write("Loading \(transcriber.identifier)...\n".data(using: .utf8)!)
        async let chunkerLoad = VADChunker.make()
        try await transcriber.warmUp()
        let chunker = try await chunkerLoad
        let dev = AudioDevices.resolve(uid: nil, name: device)
        FileHandle.standardError.write(
            "Device: \(dev?.name ?? "system default"). Speak now (\(seconds) s)...\n".data(using: .utf8)!)

        let session = DictationSession(
            transcriber: transcriber, chunker: chunker, hint: lang.hint, prompt: lang.prompt, device: dev)
        try await session.start()
        let printer = Task {
            for await event in session.events {
                switch event {
                case .chunk(let i, let text, let audio, let decode):
                    FileHandle.standardError.write(
                        "  chunk \(i): \(fmt(audio)) s audio → \(fmt(decode)) s decode: \(text)\n".data(using: .utf8)!)
                case .silentInput:
                    FileHandle.standardError.write(
                        "  ⚠️ silent input (permission denied or muted mic?)\n".data(using: .utf8)!)
                default: break
                }
            }
        }
        try await Task.sleep(for: .seconds(seconds))
        let t0 = Date()
        let text = await session.stop()
        await printer.value
        let stats = await session.stats
        FileHandle.standardError.write(
            "stop → text: \(fmt(Date().timeIntervalSince(t0))) s  |  audio \(fmt(stats.seconds)) s, peak \(String(format: "%.3f", stats.peak)), chunks \(stats.chunks)\n"
                .data(using: .utf8)!)
        print(text)
        if insert, !text.isEmpty {
            FileHandle.standardError.write("Click into a text field: 3... ".data(using: .utf8)!)
            try await Task.sleep(for: .seconds(3))
            let report = await TextInjector.insert(text)
            FileHandle.standardError.write("inserted via \(report.strategy.rawValue)\n".data(using: .utf8)!)
        }
        await transcriber.unload()
    }
}

// MARK: - inject

struct Inject: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Insert text at the caret of the frontmost app after a countdown.")

    @Argument(help: "Text to insert.") var text: String
    @Option(name: .long, help: "Seconds to wait so you can click into the target app.") var countdown: Int = 3
    @Option(name: .long, help: "Force one strategy: accessibility | paste | typing. Default: policy ladder.")
    var strategy: String?
    @Option(name: .long, help: "Event tap for synthetic keys: hid | session | annotated.") var tap: String = "hid"
    @Flag(name: .long, help: "Post events directly to the target pid instead of a tap.") var pid = false

    func run() async throws {
        guard let tapLocation = EventTap(rawValue: tap) else {
            throw ValidationError("Unknown tap '\(tap)'. Use hid | session | annotated.")
        }
        let forced: InsertionStrategy?
        if let strategy {
            guard let s = InsertionStrategy(rawValue: strategy) else {
                throw ValidationError("Unknown strategy '\(strategy)'. Use accessibility | paste | typing.")
            }
            forced = s
        } else {
            forced = nil
        }
        for i in stride(from: countdown, through: 1, by: -1) {
            FileHandle.standardError.write("\(i)... ".data(using: .utf8)!)
            try await Task.sleep(for: .seconds(1))
        }
        FileHandle.standardError.write("\n".data(using: .utf8)!)
        let report = await TextInjector.insert(text, forcedStrategy: forced, tap: tapLocation, forcePid: pid)
        print("target:   \(report.target)")
        print("strategy: \(report.strategy.rawValue)  (\(report.elapsed))")
        for (s, note) in report.attempts {
            print("  \(s.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)) \(note)")
        }
        // Read the target's value back through AX when it exposes one, so automated tests
        // can confirm the text landed without app-specific scripting.
        try await Task.sleep(for: .milliseconds(200))
        let after = await MainActor.run { FocusSnapshot.take().valueExcerpt(maxLength: 120) }
        if let after { print("after:    \(after)") }
    }
}

// MARK: - doctor

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show permission state, secure input, focused element and known models.")

    func run() async throws {
        let rows = await MainActor.run { Permissions.summary() }
        for (p, s) in rows { print("\(p.title.padding(toLength: 14, withPad: " ", startingAt: 0)) \(s.rawValue)") }
        let canPost = await MainActor.run { Permissions.canPostEvents }
        print("post events    \(canPost ? "granted" : "denied")")
        print("secure input   \(SecureInput.isEnabled ? "ACTIVE" : "off")")
        let focus = await MainActor.run { FocusSnapshot.take().description }
        print("focus          \(focus)")
        try Models().run()
    }
}

// MARK: - Shared options

struct EngineOptions: ParsableArguments {
    @Option(
        name: .long,
        help: "Model key (\(WhisperModel.catalog.map(\.id).joined(separator: ", "))) or WhisperKit variant name.")
    var model: String = WhisperModel.default.id

    @Flag(name: .long, help: "Skip CoreML prewarm (faster load, higher peak memory).")
    var noPrewarm = false

    @Flag(name: .long, help: "Verbose WhisperKit logging.")
    var verbose = false

    func makeTranscriber() throws -> WhisperKitTranscriber {
        guard let model = WhisperModel.byKey(model) else {
            throw ValidationError(
                "Unknown model '\(model)'. Known: \(WhisperModel.catalog.map(\.id).joined(separator: ", "))")
        }
        var o = WhisperKitTranscriber.Options()
        o.model = model
        o.prewarm = !noPrewarm
        o.verbose = verbose
        return WhisperKitTranscriber(options: o)
    }
}

struct LanguageOptions: ParsableArguments {
    @Option(
        name: .long, help: "Language: 'auto', an ISO code like 'cs', or a comma list to detect among (e.g. 'cs,en').")
    var language: String = "auto"

    @Option(name: .long, help: "Initial prompt / glossary that biases spelling (e.g. 'SAP, BTP, Jira, pull request').")
    var prompt: String?

    var hint: LanguageHint {
        if language == "auto" { return .auto }
        let parts = language.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.count == 1 ? .fixed(parts[0]) : .autoAmong(parts)
    }
}

func loadFixture(_ path: String) throws -> [Float] {
    try AudioFile.loadMono16k(path)
}

func fmt(_ x: Double) -> String { String(format: "%.2f", x) }

// MARK: - transcribe

struct Transcribe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Transcribe one or more 16 kHz WAV files.")

    @Argument(help: "WAV file(s).") var files: [String]
    @OptionGroup var engine: EngineOptions
    @OptionGroup var lang: LanguageOptions
    @Flag(name: .long, help: "Emit JSON.") var json = false

    func run() async throws {
        let transcriber = try engine.makeTranscriber()
        FileHandle.standardError.write("Loading \(transcriber.identifier)...\n".data(using: .utf8)!)
        try await transcriber.warmUp()
        let lt = await transcriber.loadTiming
        FileHandle.standardError.write("Loaded in \(fmt(lt.load))s (+\(fmt(lt.warmUp))s warm-up)\n".data(using: .utf8)!)

        var out: [[String: Any]] = []
        for file in files {
            let samples = try loadFixture(file)
            let r = try await transcriber.transcribe(samples, hint: lang.hint, prompt: lang.prompt)
            if json {
                out.append([
                    "file": (file as NSString).lastPathComponent,
                    "language": r.language ?? "",
                    "text": r.text,
                    "audioSeconds": r.timings.audioSeconds,
                    "totalSeconds": r.timings.totalSeconds,
                    "rtf": r.timings.realTimeFactor,
                    "avgLogProb": r.avgLogProb.map(Double.init) ?? 0,
                    "noSpeechProb": r.noSpeechProb.map(Double.init) ?? 0,
                ])
            } else {
                print(
                    "\((file as NSString).lastPathComponent): [\(r.language ?? "?")] \(fmt(r.timings.totalSeconds))s for \(fmt(r.timings.audioSeconds))s audio (RTF \(fmt(r.timings.realTimeFactor)))"
                )
                print("  \(r.text)")
            }
        }
        if json {
            let data = try JSONSerialization.data(
                withJSONObject: out, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            print(String(decoding: data, as: UTF8.self))
        }
        await transcriber.unload()
    }
}

// MARK: - detect

struct Detect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print language probabilities for WAV files.")

    @Argument(help: "WAV file(s).") var files: [String]
    @OptionGroup var engine: EngineOptions
    @Option(name: .long, help: "How many languages to print.") var top: Int = 5

    func run() async throws {
        let transcriber = try engine.makeTranscriber()
        try await transcriber.warmUp()
        for file in files {
            let samples = try loadFixture(file)
            let t0 = Date()
            let probs = try await transcriber.detectLanguage(samples)
            let dt = Date().timeIntervalSince(t0)
            let line = probs.prefix(top).map { "\($0.code)=\(String(format: "%.3f", $0.probability))" }.joined(
                separator: "  ")
            print("\((file as NSString).lastPathComponent): \(line)  (\(fmt(dt))s)")
        }
        await transcriber.unload()
    }
}

// MARK: - bench

struct Bench: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Measure load, warm-up and per-chunk latency.")

    @Argument(help: "WAV file used for the timed runs.") var file: String
    @OptionGroup var engine: EngineOptions
    @OptionGroup var lang: LanguageOptions
    @Option(name: .long, help: "Iterations.") var iterations: Int = 5

    func run() async throws {
        let transcriber = try engine.makeTranscriber()
        let t0 = Date()
        try await transcriber.warmUp()
        let lt = await transcriber.loadTiming
        print("model: \(transcriber.identifier)")
        print("load: \(fmt(lt.load))s  warm-up: \(fmt(lt.warmUp))s  total: \(fmt(Date().timeIntervalSince(t0)))s")
        let samples = try loadFixture(file)
        var totals: [Double] = []
        for i in 1...max(1, iterations) {
            let r = try await transcriber.transcribe(samples, hint: lang.hint, prompt: lang.prompt)
            totals.append(r.timings.totalSeconds)
            print(
                "run \(i): \(fmt(r.timings.totalSeconds))s (detect \(fmt(r.timings.languageDetectionSeconds))s, decode \(fmt(r.timings.decodeSeconds))s) [\(r.language ?? "?")]"
            )
        }
        let sorted = totals.sorted()
        let median = sorted[sorted.count / 2]
        print(
            "audio: \(fmt(Double(samples.count) / 16_000))s  median: \(fmt(median))s  RTF: \(fmt(median / (Double(samples.count) / 16_000)))"
        )
        await transcriber.unload()
    }
}

// MARK: - models

struct Models: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List known models and their download state.")

    func run() throws {
        let base = WhisperModel.defaultDownloadBase
        print("download base: \(base.path)")
        for m in WhisperModel.catalog {
            let present = FileManager.default.fileExists(
                atPath: base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(m.variant)").path)
            print(
                "\(m.id.padding(toLength: 20, withPad: " ", startingAt: 0)) \(m.variant.padding(toLength: 48, withPad: " ", startingAt: 0)) ~\(m.approxSizeMB) MB  \(present ? "downloaded" : "-")  \(m.note)"
            )
        }
    }
}
