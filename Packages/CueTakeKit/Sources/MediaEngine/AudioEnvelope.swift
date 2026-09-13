import Domain
import Foundation

/// The volume curve for one audio clip, as a list of ramps.
///
/// Pure arithmetic on purpose: no AVFoundation, no files, nothing to mock. Ducking is the part of
/// an editor people get wrong most often — it is easy to make music dip and hard to make it dip in
/// a way nobody notices — and the only way to get it right is to be able to reason about the curve
/// on its own, away from the mixer.
///
/// Everything is in timeline seconds relative to the start of the clip.
struct AudioEnvelope {
    struct Ramp: Hashable {
        var start: Double
        var duration: Double
        var from: Double
        var to: Double
    }

    /// How far music drops under a voice. −15 dB: far enough that the words win, close enough that
    /// the music is still playing. Dropping to silence is what makes ducking sound like a mistake.
    static let duckLevel = 0.18
    /// Down before the word, up well after it. Asymmetric because that is how ears expect it:
    /// a fast dip is invisible, a fast recovery is a pump.
    static let attack = 0.28
    static let release = 0.55

    /// Breakpoints for a clip, already multiplied by its gain.
    ///
    /// - Parameter spoken: ranges where someone is talking, in timeline seconds — absolute, the
    ///   way `Project.spokenRanges` gives them.
    static func ramps(for clip: AudioClip, spoken: [MediaTimeRange]) -> [Ramp] {
        let length = clip.timelineDuration.seconds
        guard length > 0.01 else { return [] }

        let gain = clip.isMuted ? 0 : clip.gain
        let fadeIn = min(max(0, clip.fadeIn.seconds), length / 2)
        let fadeOut = min(max(0, clip.fadeOut.seconds), length / 2)

        var points: [(t: Double, level: Double)] = []
        points.append((0, fadeIn > 0.01 ? 0 : 1))
        if fadeIn > 0.01 { points.append((fadeIn, 1)) }

        if clip.ducksUnderVoice {
            let origin = clip.start.seconds
            // Only the part of the speech that happens while this clip is playing matters, and
            // only after the fade has finished — a duck inside a fade is two curves fighting over
            // the same moment.
            let windows = merged(
                spoken.compactMap { range -> ClosedRange<Double>? in
                    let lower = range.start.seconds - origin - attack
                    let upper = range.end.seconds - origin + release
                    let clampedLower = max(lower, fadeIn)
                    let clampedUpper = min(upper, length - fadeOut)
                    guard clampedUpper - clampedLower > 0.1 else { return nil }
                    return clampedLower...clampedUpper
                }
            )

            for window in windows {
                let span = window.upperBound - window.lowerBound
                let inTime = min(attack, span / 2)
                let outTime = min(release, span / 2)
                points.append((window.lowerBound, 1))
                points.append((window.lowerBound + inTime, duckLevel))
                points.append((window.upperBound - outTime, duckLevel))
                points.append((window.upperBound, 1))
            }
        }

        if fadeOut > 0.01 { points.append((length - fadeOut, 1)) }
        points.append((length, fadeOut > 0.01 ? 0 : 1))

        points.sort { $0.t < $1.t }

        var ramps: [Ramp] = []
        for (previous, next) in zip(points, points.dropFirst()) {
            let duration = next.t - previous.t
            // Zero-length ramps are rejected by the mixer, and a flat one carries no information
            // a neighbour does not already carry.
            guard duration > 0.005 else { continue }
            ramps.append(
                Ramp(
                    start: previous.t,
                    duration: duration,
                    from: previous.level * gain,
                    to: next.level * gain
                )
            )
        }
        return ramps
    }

    /// Overlapping duck windows become one. Two sentences half a second apart should not make the
    /// music jump up between them — that bounce is the single most recognisable sign of automatic
    /// ducking done badly.
    static func merged(_ windows: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        let sorted = windows.sorted { $0.lowerBound < $1.lowerBound }
        var result: [ClosedRange<Double>] = []
        for window in sorted {
            if let last = result.last, window.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound...max(last.upperBound, window.upperBound)
            } else {
                result.append(window)
            }
        }
        return result
    }
}
