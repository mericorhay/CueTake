import Foundation

/// Seconds to points and back.
///
/// The timeline's whole character comes from this one number. Laid out proportionally — every clip
/// a share of the screen width — the timeline is a diagram: it always fits, and it can never be
/// worked on, because a fifth of a second is two pixels wide. Laid out at a scale, it is an
/// instrument: pinch until a second is wide enough to grab, and the edit becomes possible.
enum TimelineScale {
    /// Roughly a 30 second video across a phone. The scale a project opens at.
    static let fit: Double = 11
    /// Below this the clips stop being readable and there is nothing to aim at.
    static let minimum: Double = 4
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
    /// Constant in *points*, not seconds: snapping should feel the same under the finger at every
    /// zoom level, and a fixed tolerance in seconds would be unusable at one end and invisible at
    /// the other.
    static func snapTolerance(pointsPerSecond: Double) -> Double {
        10 / pointsPerSecond
    }
}
