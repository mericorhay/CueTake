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
            // Whole samples only: an empty buffer, or a stray byte past the last sample, must not
            // be copied into an array that has no room for it.
            let samples = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
            guard samples > 0 else { continue }
            var data = [Float](repeating: 0, count: samples)
            data.withUnsafeMutableBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: base)
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

    func isLoud(at seconds: Double, above extra: Float = 0) -> Bool {
        // A hair added so a time built by adding windows lands in the window it names.
        let index = Int(seconds / window + 0.0001)
        guard levels.indices.contains(index) else { return false }
        return levels[index] > threshold + extra
    }

    /// Word edges moved onto the sound.
    ///
    /// A recogniser's word times can be a tenth of a second out, which is the difference between a
    /// cut in the silence before a word and a cut through its first consonant. Each start moves
    /// back while the sound before it is still voice, or forward to where the voice begins; each
    /// end the same way. Words never cross their neighbours.
    public func snapped(_ words: [TimedWord]) -> [TimedWord] {
        var result: [TimedWord] = []
        result.reserveCapacity(words.count)
        for (index, word) in words.enumerated() {
            let floor = max(0, result.last?.range.end.seconds ?? 0)
            let ceiling = index + 1 < words.count ? words[index + 1].range.start.seconds : Double(levels.count) * window
            var start = max(word.range.start.seconds, floor)
            var end = max(word.range.end.seconds, start + 0.05)

            if isLoud(at: start) {
                var step = 0
                while step < 6, start - window >= floor, isLoud(at: start - window) {
                    start -= window
                    step += 1
                }
            } else {
                var probe = start
                let limit = min(word.range.start.seconds + 0.15, end - 0.05)
                while !isLoud(at: probe), probe + window <= limit {
                    probe += window
                }
                if isLoud(at: probe) { start = probe }
            }

            if isLoud(at: end - window) {
                var step = 0
                while step < 7, end + window <= ceiling, isLoud(at: end) {
                    end += window
                    step += 1
                }
            } else {
                var probe = end
                while probe - window > max(start + 0.05, word.range.end.seconds - 0.15), !isLoud(at: probe - window) {
                    probe -= window
                }
                end = probe
            }

            var moved = word
            moved.range = MediaTimeRange(
                start: MediaTime(seconds: start),
                duration: MediaTime(seconds: max(0.05, end - start))
            )
            result.append(moved)
        }
        return result
    }

    /// Stretches between words where there is clearly voice — louder than a breath — but no word:
    /// the "ııı"s and "hmm"s recognisers leave out. `words` may come from several listeners.
    public func unheardSounds(between words: [TimedWord], shortest: Double = 0.12, longest: Double = 1.5) -> [ClosedRange<Double>] {
        let sorted = words.sorted { $0.range.start.seconds < $1.range.start.seconds }
        var sounds: [ClosedRange<Double>] = []
        for (left, right) in zip(sorted, sorted.dropFirst()) {
            let from = left.range.end.seconds + 0.05
            let to = right.range.start.seconds - 0.05
            guard to - from >= shortest else { continue }
            var runs: [ClosedRange<Double>] = []
            var runStart: Double?
            var time = from
            while time < to {
                if isLoud(at: time, above: 6) {
                    if runStart == nil { runStart = time }
                } else if let begun = runStart {
                    runs.append(begun...time)
                    runStart = nil
                }
                time += window
            }
            if let begun = runStart { runs.append(begun...to) }

            // Runs a moment apart are one sound.
            var merged: [ClosedRange<Double>] = []
            for run in runs {
                if let last = merged.last, run.lowerBound - last.upperBound < 0.1 {
                    merged[merged.count - 1] = last.lowerBound...run.upperBound
                } else {
                    merged.append(run)
                }
            }
            sounds += merged.filter { ($0.upperBound - $0.lowerBound) >= shortest && ($0.upperBound - $0.lowerBound) <= longest }
        }
        return sounds
    }
}
