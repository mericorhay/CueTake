import Accelerate
import AVFoundation
import Domain
import Foundation

/// Finds the beats of a piece of music on the phone.
///
/// The classic recipe, kept small: an onset curve from the rise of energy (the low band weighted
/// up, where kicks live), tempo from the curve's autocorrelation with a gentle preference for
/// dance and pop tempos, the grid's phase from where the curve is strongest, each beat nudged to
/// its nearest peak, and bars from the four-beat phase with the most weight. It reads at most ten
/// minutes, a few seconds of work for a song.
public enum BeatDetector {
    static let hop = 512
    static let analysisRate = 22_050.0

    public static func grid(for url: URL) async -> BeatGrid? {
        await Task.detached(priority: .userInitiated) { () -> BeatGrid? in
            guard let samples = try? monoSamples(url) else { return nil }
            return grid(samples: samples, sampleRate: analysisRate)
        }.value
    }

    /// Mono samples at `analysisRate`, the first ten minutes.
    static func monoSamples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: analysisRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: target)
        else { return [] }
        let limit = AVAudioFramePosition(file.processingFormat.sampleRate * 600)
        var output: [Float] = []
        let chunk: AVAudioFrameCount = 16_384
        var finished = false
        while !finished {
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: chunk) else { break }
            var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, state in
                guard file.framePosition < min(file.length, limit),
                      let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk),
                      (try? file.read(into: input, frameCount: chunk)) != nil, input.frameLength > 0
                else {
                    state.pointee = .endOfStream
                    return nil
                }
                state.pointee = .haveData
                return input
            }
            if let data = out.floatChannelData?[0], out.frameLength > 0 {
                output.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(out.frameLength)))
            }
            if status == .endOfStream || status == .error || out.frameLength == 0 { finished = true }
        }
        return output
    }

    static func grid(samples: [Float], sampleRate: Double) -> BeatGrid? {
        let frameSeconds = Double(hop) / sampleRate
        let count = samples.count / hop
        guard count > Int(8 / frameSeconds) else { return nil }

        // Energy per hop: all of it, and the low band (a one-pole low-pass around 150 Hz).
        var low: Float = 0
        let alpha = Float(1 - exp(-2 * Double.pi * 150 / sampleRate))
        var full = [Float](repeating: 0, count: count)
        var bass = [Float](repeating: 0, count: count)
        for frame in 0..<count {
            var e: Float = 0
            var b: Float = 0
            let base = frame * hop
            for i in base..<(base + hop) {
                let x = samples[i]
                low += alpha * (x - low)
                e += x * x
                b += low * low
            }
            full[frame] = log1p(e * 100)
            bass[frame] = log1p(b * 100)
        }

        // Onsets: the rise of energy, the bass counting double, less its local average.
        var onset = [Float](repeating: 0, count: count)
        for frame in 1..<count {
            onset[frame] = max(0, full[frame] - full[frame - 1]) + 2 * max(0, bass[frame] - bass[frame - 1])
        }
        let window = max(1, Int(0.4 / frameSeconds))
        var smoothed = [Float](repeating: 0, count: count)
        var running: Float = 0
        for frame in 0..<count {
            running += onset[frame]
            if frame >= window { running -= onset[frame - window] }
            smoothed[frame] = max(0, onset[frame] - running / Float(min(frame + 1, window)))
        }

        // Tempo: the lag, between 70 and 180 BPM, where the curve best matches itself, leaning
        // towards 120 so a song is not read at half or double its speed.
        let minLag = Int((60 / 180) / frameSeconds)
        let maxLag = Int((60 / 70) / frameSeconds)
        var bestLag = 0
        var bestScore: Float = -.infinity
        for lag in minLag...maxLag {
            var score: Float = 0
            vDSP_dotpr(smoothed, 1, Array(smoothed[lag...]), 1, &score, vDSP_Length(count - lag))
            let bpm = 60 / (Double(lag) * frameSeconds)
            let preference = Float(exp(-0.5 * pow(log2(bpm / 120) / 0.9, 2)))
            score *= preference
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }
        guard bestLag > 0 else { return nil }

        // The kick's own rise, which says where the beat is rather than the hi-hat between.
        var kick = [Float](repeating: 0, count: count)
        for frame in 1..<count { kick[frame] = max(0, bass[frame] - bass[frame - 1]) }
        var strength = [Float](repeating: 0, count: count)
        for frame in 0..<count { strength[frame] = smoothed[frame] + 2 * kick[frame] }

        // The exact period and phase: whole-hop lags drift a beat off within a minute, so every
        // period within a hop and a half of the lag is tried, each at its best phase.
        func value(at position: Double) -> Float {
            let i = Int(position)
            guard i + 1 < count else { return i < count ? strength[i] : 0 }
            let f = Float(position - Double(i))
            return strength[i] * (1 - f) + strength[i + 1] * f
        }
        var period = Double(bestLag)
        var phase = 0.0
        var best: Float = -.infinity
        for candidate in stride(from: Double(bestLag) - 1.5, through: Double(bestLag) + 1.5, by: 0.05) {
            for offset in stride(from: 0.0, to: candidate, by: 0.5) {
                var sum: Float = 0
                var position = offset
                while position < Double(count - 1) {
                    sum += value(at: position)
                    position += candidate
                }
                if sum > best {
                    best = sum
                    period = candidate
                    phase = offset
                }
            }
        }

        // Every beat, pulled a little towards the strongest onset near where the grid puts it.
        let reach = max(1, Int(period * 0.1))
        var beats: [Double] = []
        var strengths: [Float] = []
        var position = phase
        while Int(position) < count {
            let centre = Int(position.rounded())
            let lower = max(0, centre - reach)
            let upper = min(count - 1, centre + reach)
            var peak = min(centre, count - 1)
            var peakValue: Float = -1
            if lower <= upper {
                for i in lower...upper where strength[i] > peakValue {
                    peakValue = strength[i]
                    peak = i
                }
            }
            beats.append(Double(peak) * frameSeconds)
            strengths.append(max(0, peakValue))
            position += period + 0.2 * (Double(peak) - position)
        }
        guard beats.count >= 8 else { return nil }

        // Bars: of the four ways to group beats in fours, the one whose first beats hit hardest.
        var barPhase = 0
        var barScore: Float = -.infinity
        for phase in 0..<4 {
            let sum = stride(from: phase, to: strengths.count, by: 4).reduce(Float(0)) { $0 + strengths[$1] }
            if sum > barScore {
                barScore = sum
                barPhase = phase
            }
        }
        let downbeats = stride(from: barPhase, to: beats.count, by: 4).map { beats[$0] }
        let bpm = 60 / (period * frameSeconds)
        return BeatGrid(bpm: (bpm * 10).rounded() / 10, beats: beats, downbeats: downbeats)
    }
}
