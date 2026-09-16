import Foundation

/// Seconds to points and back.
///
/// The timeline's whole character comes from this one number. Laid out proportionally — every clip
/// a share of the screen width — the timeline is a diagram: it always fits, and it can never be
/// worked on, because a fifth of a second is two pixels wide. Laid out at a scale, it is an
/// instrument: pinch until a second is wide enough to grab, and the edit becomes possible.
enum TimelineScale {
    /// About one 30 fps frame per point. The previous 11 pt/s made one pixel almost a tenth of a
    /// second and turned a small scrub into guesswork even on a Pro Max.
    static let fit: Double = 32
    /// Below this the clips stop being readable and there is nothing to aim at.
    static let minimum: Double = 8
    /// A second is most of the screen. Enough to place a cut inside a word.
    static let maximum: Double = 240

    static func clamp(_ pointsPerSecond: Double) -> Double {
        min(max(minimum, pointsPerSecond), maximum)
    }

    /// How far apart to draw the ruler's labelled ticks, so they never crowd.
    ///
    /// The steps are the ones a person thinks in — a second, five, fifteen, a minute — rather than
    /// whatever falls out of the arithmetic. A ruler marked every 3.7 seconds is technically
    /// even spacing and useless for finding anything.
    static func tickInterval(pointsPerSecond: Double) -> Double {
        let candidates: [Double] = [0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60]
        let minimumSpacing: Double = 56
        return candidates.first { $0 * pointsPerSecond >= minimumSpacing } ?? 120
    }

    /// How close the finger has to be to a boundary before it snaps, in seconds.
    ///
    /// Primarily constant in points so snapping feels stable under the finger, with a short time
    /// ceiling so overview mode never swallows a nearby frame.
    static func snapTolerance(pointsPerSecond: Double) -> Double {
        // At overview scale ten points used to pull the playhead back almost a full second. Keep
        // nearby frames reachable while preserving a comfortable physical target.
        min(0.12, 10 / max(pointsPerSecond, 1))
    }
}
