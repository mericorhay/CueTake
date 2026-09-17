import AVFoundation
import Foundation

/// The voice's volume over the video, with a short dip at every join.
///
/// Wherever two pieces of sound are laid end to end — a cleaned pause, a cut filler, the next clip —
/// the waveform jumps, and a jump is a click. A 20 ms fade out and in on each side of the join
/// removes it without being heard as a fade. Levels between joins are held as set.
enum VoiceSplices {
    enum Step: Equatable {
        case set(at: Double, value: Double)
        case ramp(from: Double, to: Double, start: Double, end: Double)
    }

    /// `levels` are the gains from each join onwards, in seconds on the finished video.
    static func envelope(levels: [(time: Double, gain: Double)], fade: Double = 0.02) -> [Step] {
        // One gain per moment, the last one given winning.
        var points: [(time: Double, gain: Double)] = []
        for level in levels.sorted(by: { $0.time < $1.time }) {
            if let last = points.last, abs(last.time - level.time) < 0.0005 {
                points[points.count - 1] = level
            } else {
                points.append(level)
            }
        }

        var steps: [Step] = []
        var previousEnd = -Double.infinity
        for (i, point) in points.enumerated() {
            let time = point.time
            let next = i + 1 < points.count ? points[i + 1].time : Double.infinity
            guard i > 0, time > fade else {
                steps.append(.set(at: max(0, time), value: point.gain))
                previousEnd = max(0, time)
                continue
            }
            let before = points[i - 1].gain
            let downStart = max(time - fade, previousEnd)
            if before > 0, time - downStart > 0.004 {
                steps.append(.ramp(from: before, to: 0, start: downStart, end: time))
            }
            // The rise must finish before the next join's dip begins.
            let upEnd = min(time + fade, time + max(0, (next - time) / 2))
            if point.gain > 0, upEnd - time > 0.004 {
                steps.append(.ramp(from: 0, to: point.gain, start: time, end: upEnd))
                previousEnd = upEnd
            } else {
                steps.append(.set(at: time, value: point.gain))
                previousEnd = time
            }
        }
        return steps
    }

    /// Writes the envelope onto the voice, scaled by the main volume.
    static func apply(_ steps: [Step], volume: Float, to input: AVMutableAudioMixInputParameters) {
        guard volume > 0 else {
            input.setVolume(0, at: .zero)
            return
        }
        var previousEnd = CMTime.zero
        var wroteStart = false
        for step in steps {
            switch step {
            case .set(let at, let value):
                let time = CMTimeMaximum(CMTime(seconds: at, preferredTimescale: 600), previousEnd)
                input.setVolume(volume * Float(value), at: time)
                wroteStart = true
            case .ramp(let from, let to, let start, let end):
                // Ramps sit on whole ticks and never overlap: AVFoundation raises an exception
                // Swift cannot catch for overlapping ramps.
                let a = CMTimeMaximum(CMTime(seconds: start, preferredTimescale: 600), previousEnd)
                let b = CMTime(seconds: end, preferredTimescale: 600)
                guard b > a, abs(from - to) > 0.0001 else { continue }
                if !wroteStart {
                    input.setVolume(volume * Float(from), at: .zero)
                    wroteStart = true
                }
                input.setVolumeRamp(
                    fromStartVolume: volume * Float(from),
                    toEndVolume: volume * Float(to),
                    timeRange: CMTimeRange(start: a, end: b)
                )
                previousEnd = b
            }
        }
        if !wroteStart {
            input.setVolume(volume, at: .zero)
        }
    }
}
