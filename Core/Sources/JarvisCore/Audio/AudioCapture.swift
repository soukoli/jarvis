import AVFoundation
import CoreMedia
import Foundation

/// Events from the microphone.
public enum CaptureEvent: Sendable {
    /// 16 kHz mono Float32 samples.
    case audio([Float])
    /// About two seconds of all-zero samples arrived: the mic is muted or permission is denied.
    case silentInput
    /// The session started but the device delivered no buffers within the watchdog window
    /// (typical for a Bluetooth headset whose microphone did not wake up).
    case noInput(deviceName: String)
    case ended
}

/// Microphone capture with `AVCaptureSession`.
///
/// Why not `AVAudioEngine`: selecting a specific input device on its input node (via the
/// `kAudioOutputUnitProperty_CurrentDevice` audio-unit property) proved unreliable on macOS 27:
/// stale formats after a device change, `-10868` on start, or silent taps. `AVCaptureSession`
/// picks a device by unique id, negotiates the format, and on macOS can deliver 16 kHz mono
/// Float32 directly, so no converter is needed.
public final class AudioCapture: NSObject, @unchecked Sendable {
    public static let targetSampleRate: Double = 16_000

    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "com.sap.jarvis.capture", qos: .userInteractive)
    private var continuation: AsyncStream<CaptureEvent>.Continuation?
    private let lock = NSLock()
    private var isRunning = false
    private var diagnostics: TapDiagnostics?

    // Silent-input detection state (touched only on `queue`).
    private var silentSamples = 0
    private var seenSamples = 0
    private var silenceChecked = false

    public override init() { super.init() }

    /// Start capturing. Returns the event stream; call `stop()` to end it.
    public func start(device: AudioInputDevice? = nil) throws -> AsyncStream<CaptureEvent> {
        lock.lock()
        defer { lock.unlock() }
        precondition(!isRunning, "AudioCapture already running")

        let captureDevice: AVCaptureDevice
        if let device, let d = AVCaptureDevice(uniqueID: device.uid) {
            captureDevice = d
        } else if let d = AVCaptureDevice.default(for: .audio) {
            captureDevice = d
        } else {
            throw CaptureError.noInputDevice
        }

        session.beginConfiguration()
        for input in session.inputs { session.removeInput(input) }
        for out in session.outputs { session.removeOutput(out) }
        let input = try AVCaptureDeviceInput(device: captureDevice)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CaptureError.cannotAddInput
        }
        session.addInput(input)
        // macOS lets the audio output resample and mix down for us.
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.targetSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CaptureError.cannotAddOutput
        }
        session.addOutput(output)
        session.commitConfiguration()

        let (stream, continuation) = AsyncStream<CaptureEvent>.makeStream(bufferingPolicy: .unbounded)
        self.continuation = continuation
        let diag = TapDiagnostics()
        diag.startedAt = Date()
        diagnostics = diag
        silentSamples = 0
        seenSamples = 0
        silenceChecked = false

        session.startRunning()
        guard session.isRunning else {
            self.continuation = nil
            throw CaptureError.sessionDidNotStart
        }
        isRunning = true
        Log.audio.info(
            "capture started on \(captureDevice.localizedName, privacy: .public) [\(captureDevice.uniqueID, privacy: .public)]"
        )

        // Watchdog: a device that never delivers would otherwise fail silently. Switching from a
        // Bluetooth device to the built-in mic can take CoreAudio a couple of seconds.
        let deviceName = captureDevice.localizedName
        queue.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, self.isRunning, diag.callbacks == 0 else { return }
            Log.audio.error("no audio from \(deviceName, privacy: .public) after 3 s")
            self.continuation?.yield(.noInput(deviceName: deviceName))
        }
        return stream
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard isRunning else { return }
        session.stopRunning()
        isRunning = false
        continuation?.yield(.ended)
        continuation?.finish()
        continuation = nil
        if let d = diagnostics {
            Log.audio.info(
                "capture stopped: \(d.callbacks, privacy: .public) buffers (first after \(d.firstCallbackAfter, format: .fixed(precision: 2), privacy: .public) s, \(d.actualSampleRate, privacy: .public) Hz/\(d.actualChannels, privacy: .public) ch), \(d.outputFrames, privacy: .public) frames, \(d.errors, privacy: .public) errors\(d.lastError.map { " (\($0))" } ?? "", privacy: .public)"
            )
        }
    }

    deinit { stop() }
}

extension AudioCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        guard let diag = diagnostics, let continuation else { return }
        if diag.callbacks == 0 {
            diag.firstCallbackAfter = Date().timeIntervalSince(diag.startedAt)
            if let desc = CMSampleBufferGetFormatDescription(sampleBuffer),
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee
            {
                diag.actualSampleRate = asbd.mSampleRate
                diag.actualChannels = Int(asbd.mChannelsPerFrame)
                if asbd.mSampleRate != Self.targetSampleRate || asbd.mChannelsPerFrame != 1
                    || asbd.mBitsPerChannel != 32
                {
                    diag.errors += 1
                    diag.lastError =
                        "unexpected format \(asbd.mSampleRate) Hz/\(asbd.mChannelsPerFrame) ch/\(asbd.mBitsPerChannel) bit"
                }
            }
        }
        diag.callbacks += 1

        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0, let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var samples = [Float](repeating: 0, count: frames)
        let byteCount = frames * MemoryLayout<Float>.size
        let status = samples.withUnsafeMutableBytes { raw in
            CMBlockBufferCopyDataBytes(
                block, atOffset: 0, dataLength: min(byteCount, CMBlockBufferGetDataLength(block)),
                destination: raw.baseAddress!)
        }
        guard status == kCMBlockBufferNoErr else {
            diag.errors += 1
            return
        }
        diag.outputFrames += frames

        if !silenceChecked {
            seenSamples += frames
            if samples.allSatisfy({ $0 == 0 }) { silentSamples += frames }
            let window = Int(Self.targetSampleRate * 2)
            if seenSamples >= window {
                silenceChecked = true
                if Double(silentSamples) >= Double(window) * 0.95 { continuation.yield(.silentInput) }
            }
        }
        continuation.yield(.audio(samples))
    }
}

public enum CaptureError: Error, CustomStringConvertible {
    case noInputDevice
    case cannotAddInput
    case cannotAddOutput
    case sessionDidNotStart

    public var description: String {
        switch self {
        case .noInputDevice: return "No audio input device available"
        case .cannotAddInput: return "Cannot use this microphone (is it in use by another app?)"
        case .cannotAddOutput: return "Cannot configure audio output"
        case .sessionDidNotStart: return "Audio capture did not start (Microphone permission?)"
        }
    }
}

/// Counters written from the capture queue, read once at stop. Diagnostics only.
final class TapDiagnostics: @unchecked Sendable {
    var startedAt = Date()
    var callbacks = 0
    var firstCallbackAfter: Double = -1
    var actualSampleRate: Double = 0
    var actualChannels = 0
    var outputFrames = 0
    var errors = 0
    var lastError: String?
}
