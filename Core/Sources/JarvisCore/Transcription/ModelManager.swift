import Foundation
import Observation
import WhisperKit

/// Loads and switches speech models, reporting progress for the UI. Owns the live transcriber and
/// the VAD chunker. Model loading happens off the main thread; only status updates hop back.
@MainActor
@Observable
public final class ModelManager {
    public enum Status: Sendable, Equatable {
        case idle
        case downloading(Double)  // 0...1
        case loading  // CoreML compile / ANE specialization
        case ready
        case failed(String)

        public var isReady: Bool { self == .ready }
        public var label: String {
            switch self {
            case .idle: return "Not loaded"
            case .downloading(let p): return "Downloading \(Int(p * 100)) %"
            case .loading: return "Preparing model…"
            case .ready: return "Ready"
            case .failed(let m): return "Failed: \(m)"
            }
        }
    }

    public private(set) var status: Status = .idle
    public private(set) var loadedModel: WhisperModel?
    public private(set) var transcriber: WhisperKitTranscriber?
    public private(set) var chunker: VADChunker?
    public private(set) var lastLoadSeconds: Double = 0

    private var loadTask: Task<Void, Never>?
    private var vadConfig: VADChunker.Config

    public init(vadConfig: VADChunker.Config = VADChunker.Config()) {
        self.vadConfig = vadConfig
    }

    public static func isDownloaded(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: Self.folder(for: model).path)
    }

    public static func folder(for model: WhisperModel) -> URL {
        WhisperModel.defaultDownloadBase
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(model.variant)", isDirectory: true)
    }

    /// Load `model` (download first if needed). Cancels a load in flight. Safe to call repeatedly.
    public func load(_ model: WhisperModel) {
        if loadedModel == model, status.isReady { return }
        loadTask?.cancel()
        status = Self.isDownloaded(model) ? .loading : .downloading(0)
        let vadConfig = vadConfig
        let previous = transcriber
        loadTask = Task { [weak self] in
            // `self` is a weak var here; nested closures need an immutable copy.
            let owner: ModelManager? = self
            let started = Date()
            do {
                let folder: URL
                if Self.isDownloaded(model) {
                    folder = Self.folder(for: model)
                } else {
                    folder = try await WhisperKit.download(
                        variant: model.variant,
                        downloadBase: WhisperModel.defaultDownloadBase,
                        progressCallback: { progress in
                            let fraction = progress.fractionCompleted
                            Task { @MainActor in
                                if case .downloading = owner?.status { owner?.status = .downloading(fraction) }
                            }
                        }
                    )
                }
                try Task.checkCancellation()
                await MainActor.run { owner?.status = .loading }

                var options = WhisperKitTranscriber.Options()
                options.model = model
                options.modelFolder = folder
                let transcriber = WhisperKitTranscriber(options: options)
                async let chunkerLoad = VADChunker.make(config: vadConfig)
                try await transcriber.warmUp()
                let chunker = try await chunkerLoad
                try Task.checkCancellation()
                await previous?.unload()

                await MainActor.run {
                    guard let owner else { return }
                    owner.transcriber = transcriber
                    owner.chunker = chunker
                    owner.loadedModel = model
                    owner.lastLoadSeconds = Date().timeIntervalSince(started)
                    owner.status = .ready
                    Log.models.info(
                        "model \(model.variant, privacy: .public) ready in \(owner.lastLoadSeconds, privacy: .public) s"
                    )
                }
            } catch is CancellationError {
                // superseded by a newer load
            } catch {
                await MainActor.run {
                    owner?.status = .failed(String(describing: error))
                    Log.models.error("model load failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    /// Rebuild the chunker with new VAD parameters (cheap; the VAD model is tiny).
    public func updateVAD(_ config: VADChunker.Config) {
        vadConfig = config
        guard status.isReady else { return }
        Task { [weak self] in
            if let chunker = try? await VADChunker.make(config: config) {
                await MainActor.run { self?.chunker = chunker }
            }
        }
    }

    public func unload() {
        loadTask?.cancel()
        let t = transcriber
        transcriber = nil
        chunker = nil
        loadedModel = nil
        status = .idle
        Task { await t?.unload() }
    }
}
