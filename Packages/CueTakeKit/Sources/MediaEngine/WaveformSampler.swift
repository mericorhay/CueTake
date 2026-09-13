import AVFoundation
import Foundation

/// Peak levels along a piece of audio, for drawing it.
///
/// A waveform is not decoration. It is the only way to find a moment in a sound without listening
/// to all of it — a breath, a downbeat, the gap before the chorus — and an audio lane drawn as a
/// flat bar makes the user scrub blind. This is the cheapest honest version: peaks per bucket, one
/// bucket per column of pixels the lane will draw.
public struct WaveformSampler: Sendable {
    public init() {}

    /// Normalised 0…1 peaks, `buckets` of them.
    ///
    /// Empty when the file cannot be read, and the lane draws a flat line rather than refusing to
    /// exist — a waveform that failed should cost the user nothing.
    public func peaks(of url: URL, buckets: Int = 320) async -> [Float] {
        await Task.detached(priority: .utility) {
            (try? Self.read(url, buckets: max(8, buckets))) ?? []
        }.value
    }

    static func read(_ url: URL, buckets: Int) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let total = file.length
        guard total > 0 else { return [] }

        let chunk: AVAudioFrameCount = 32768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return [] }

        var peaks = [Float](repeating: 0, count: buckets)
        let framesPerBucket = max(1, Double(total) / Double(buckets))
        var position: Int64 = 0

        while position < total {
            try file.read(into: buffer, frameCount: chunk)
            let count = Int(buffer.frameLength)
            guard count > 0, let channel = buffer.floatChannelData?[0] else { break }

            for index in 0..<count {
                let bucket = min(buckets - 1, Int(Double(position + Int64(index)) / framesPerBucket))
                let value = abs(channel[index])
                if value > peaks[bucket] { peaks[bucket] = value }
            }
            position += Int64(count)
        }

        // Normalised to the loudest point rather than to full scale. A quiet recording drawn
        // against absolute zero dB is a flat line, which tells the user their file is broken when
        // it is only quiet.
        let loudest = peaks.max() ?? 0
        guard loudest > 0.0001 else { return peaks }
        return peaks.map { $0 / loudest }
    }
}
