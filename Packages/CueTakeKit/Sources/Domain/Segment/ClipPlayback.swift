import Foundation

/// How a segment's footage is played: its speed, whether it runs backwards, and whether it runs
/// at all.
///
/// One value rather than three loose fields, because they are not independent — a frozen frame has
/// no speed and nothing to reverse — and keeping them together is what lets `timelineSeconds` be
/// the single answer to "how long is this on the timeline". Every layout in the app asks that
/// question, and three places computing it separately is three places to get it wrong.
public struct ClipPlayback: Hashable, Sendable, Codable {
    /// 1 is as shot. Below 1 is slow motion, above is fast.
    public var speed: Double
    public var isReversed: Bool
    /// When set, the clip does not play: its first frame is held for this long.
    ///
    /// Optional rather than a duration plus a flag, so "frozen" and "for how long" cannot disagree.
    public var freeze: MediaTime?

    public init(speed: Double = 1, isReversed: Bool = false, freeze: MediaTime? = nil) {
        self.speed = speed
        self.isReversed = isReversed
        self.freeze = freeze
    }

    public static let normal = ClipPlayback()

    /// What the speed control offers.
    ///
    /// Fixed steps, not a slider: nobody wants 1.07×, and a slider would spend most of its travel
    /// between values that look identical. 0.25× is where slow motion needs a high frame rate
    /// behind it to hold up, which is why the frame-rate control exists.
    public static let speedChoices: [Double] = [0.25, 0.5, 1, 1.5, 2, 4]

    public var isModified: Bool {
        freeze != nil || isReversed || abs(speed - 1) > 0.001
    }

    /// How long `source` seconds of footage occupy the timeline under this playback.
    ///
    /// A freeze answers with its own duration and ignores the source entirely — that is the whole
    /// point of it: the footage is no longer what decides the length.
    public func timelineSeconds(forSource source: Double) -> Double {
        if let freeze { return max(0.1, freeze.seconds) }
        return source / min(max(speed, 0.1), 8)
    }

    /// The inverse, for turning a drag on the timeline back into a trim of the source.
    public func sourceSeconds(forTimeline timeline: Double) -> Double {
        timeline * min(max(speed, 0.1), 8)
    }

    /// The source offset displayed at a timeline moment. This is the shared clock conversion for
    /// preview geometry, tracking and camera lanes; a held frame always stays on its first frame.
    public func sourceOffset(forTimeline timeline: Double, sourceLength: Double) -> Double {
        let length = max(0, sourceLength)
        guard freeze == nil else { return 0 }
        let forward = min(max(sourceSeconds(forTimeline: timeline), 0), length)
        return isReversed ? length - forward : forward
    }

    /// Converts a source point back to the visible timeline. A freeze has no moving source clock,
    /// so authored motion has no meaningful lane position while it is held.
    public func timelineOffset(forSourceOffset source: Double, sourceLength: Double) -> Double? {
        let length = max(0, sourceLength)
        guard freeze == nil, source >= -0.0001, source <= length + 0.0001 else { return nil }
        let played = isReversed ? length - source : source
        return timelineSeconds(forSource: min(max(played, 0), length))
    }

    /// A short label for the badge on the clip. Nil when there is nothing worth saying.
    public var badge: String? {
        if freeze != nil { return "FREEZE" }
        var parts: [String] = []
        if abs(speed - 1) > 0.001 {
            parts.append(speed == speed.rounded() ? "\(Int(speed))×" : "\(speed)×")
        }
        if isReversed { parts.append("REV") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
