import AVFoundation
import Domain
import Foundation

/// Where a recording actually has sound in it, measured from the file.
///
/// Speech recognisers invent words. The phone's own listener sometimes puts a word at the very
/// first moment of a silent file, and Whisper is known for whole sentences read out of silence
/// ("thanks for watching"). Both are caught the same way: a word that sits where the file is as
/// quiet as its quietest moments was not said.
public struct VoiceActivity: Sendable {
    /// Loudness of each window, in dBFS.
    let levels: [Float]
    /// Seconds per window.
    let window: Double
    /// Loudness below which a window counts as silence.
    let threshold: Float

    init(levels: [Float], window: Double) {
        self.levels = levels
        self.window = window
        // The noise floor is the quiet end of the file, not its minimum — a single dropped sample
        // would otherwise set it. Speech sits well above it; a word in a stretch within a few
        // decibels of it is a word nobody said.
        let sorted = levels.sorted()
        let floor = sorted.isEmpty ? -90 : sorted[min(sorted.count - 1, sorted.count / 10)]
        threshold = max(floor + 6, -58)
    }

    /// Measures a file's sound in 20 ms windows. Nil when the file has no sound to read.
    @concurrent
    public static func measure(_ url: URL) async -> VoiceActivity? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset)
        else { return nil }
        let rate = 16_000.0
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        let perWindow = Int(rate * 0.02)
        var levels: [Float] = []
        var sum: Float = 0
        var count = 0
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var data = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            data.withUnsafeMutableBytes { bytes in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
            }
            for value in data {
                sum += value * value
                count += 1
                if count == perWindow {
                    levels.append(10 * log10(max(sum / Float(count), 1e-10)))
                    sum = 0
                    count = 0
                }
            }
        }
        guard reader.status == .completed, !levels.isEmpty else { return nil }
        return VoiceActivity(levels: levels, window: 0.02)
    }

    /// Whether anything louder than the floor happens between `start` and `end`.
    ///
    /// Generous at the edges — a recogniser's timing can be a tenth of a second out — and satisfied
    /// by a short burst, because a short word is a short burst.
    public func hasSound(from start: Double, to end: Double) -> Bool {
        let first = max(0, Int((start - 0.12) / window))
        let last = min(levels.count - 1, Int((end + 0.12) / window))
        guard first <= last else { return false }
        var loud = 0
        for index in first...last where levels[index] > threshold {
            loud += 1
            if loud >= 3 { return true }
        }
        return false
    }

    /// The words that fall where there is sound.
    public func voiced(_ words: [TimedWord]) -> [TimedWord] {
        words.filter { hasSound(from: $0.range.start.seconds, to: $0.range.end.seconds) }
    }
}
