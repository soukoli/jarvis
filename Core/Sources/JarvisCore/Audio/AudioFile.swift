import AVFoundation
import Foundation

/// Reads audio files into the 16 kHz mono Float32 form every engine in Jarvis consumes.
public enum AudioFile {
    public static let sampleRate: Double = 16_000

    public static func loadMono16k(_ path: String) throws -> [Float] {
        let url = URL(fileURLWithPath: path)
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
        else {
            throw AudioFileError.formatUnavailable
        }
        let frameCount = AVAudioFrameCount(file.length)
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: max(frameCount, 1)) else {
            throw AudioFileError.formatUnavailable
        }
        try file.read(into: inBuffer)

        if sourceFormat.sampleRate == sampleRate, sourceFormat.channelCount == 1,
            sourceFormat.commonFormat == .pcmFormatFloat32
        {
            return Array(UnsafeBufferPointer(start: inBuffer.floatChannelData![0], count: Int(inBuffer.frameLength)))
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioFileError.formatUnavailable
        }
        let ratio = sampleRate / sourceFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inBuffer.frameLength) * ratio) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
            throw AudioFileError.formatUnavailable
        }
        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: outBuffer, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inBuffer
        }
        if let conversionError { throw conversionError }
        guard status != .error else { throw AudioFileError.conversionFailed }
        return Array(UnsafeBufferPointer(start: outBuffer.floatChannelData![0], count: Int(outBuffer.frameLength)))
    }
}

public enum AudioFileError: Error {
    case formatUnavailable
    case conversionFailed
}
