import Foundation

// The worked example from the design: a Turkish 30-second iPhone review reel.
// Used by previews and as the seed project until recording and persistence are implemented.

extension SegmentRole {
    /// Stable index into the design's segment palette (hook, intro, point, example, CTA).
    public var paletteIndex: Int {
        switch self {
        case .hook: 0
        case .intro: 1
        case .mainPoint: 2
        case .example: 3
        case .callToAction: 4
        case .custom: 5
        }
    }
}

extension Segment {
    static func sample(role: SegmentRole, script: String, seconds: Double) -> Segment {
        Segment(
            role: role,
            title: role.displayLabel.capitalized,
            script: script,
            estimatedDuration: MediaTime(seconds: seconds)
        )
    }
}

extension Project {
    /// The design's blueprint: HOOK · INTRO · POINT · CTA, 0:30 total.
    public static var sample: Project {
        Project(
            title: "iPhone 17 Pro Max Camera",
            format: .vertical1080,
            localeIdentifier: "tr-TR",
            segments: [
                .sample(
                    role: .hook,
                    script: "Bu telefonun kamerası gerçekten abartıldığı kadar iyi mi?",
                    seconds: 4
                ),
                .sample(
                    role: .intro,
                    script: "iPhone 17 Pro Max’i üç gündür test ediyorum ve tek bir özellik her şeyi değiştirdi.",
                    seconds: 5
                ),
                .sample(
                    role: .mainPoint,
                    script: "48 megapiksellik ana sensör gece çekimlerinde ışığı tamamen farklı topluyor. "
                        + "Aynı sahneyi geçen yılki modelle de çektim, fark ekranda bile belli oluyor.",
                    seconds: 11
                ),
                .sample(
                    role: .callToAction,
                    script: "Tam karşılaştırmayı görmek istiyorsan takip et, yarın gece yayında.",
                    seconds: 10
                ),
            ]
        )
    }

    /// Total of the segments' estimated durations, e.g. "0:30".
    public var estimatedTotalLabel: String {
        let seconds = segments.reduce(0.0) { total, segment in
            total + segment.estimatedSpeakingDuration(
                wordsPerMinute: SpeakingRate.wordsPerMinute(forLocaleIdentifier: localeIdentifier)
            ).seconds
        }
        return MediaTime(seconds: seconds).timecode
    }

    public var wordCount: Int {
        segments.reduce(0) { $0 + ScriptText.words(in: $1.script).count }
    }
}

extension MediaTime {
    /// "m:ss", as the design formats every duration.
    ///
    /// Counted down, not rounded: a playhead half a second in is at 0:00, the way every clock and
    /// player counts. Rounding showed 0:01 there, and the clock ran a second ahead of the picture.
    public var timecode: String {
        let total = Int(max(0, seconds + 0.001).rounded(.down))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}

extension MediaTime {
    /// "m:ss.t", for a playhead that has to be placed rather than read at a glance.
    public var preciseTimecode: String {
        let clamped = max(0, seconds + 0.0001)
        let whole = Int(clamped.rounded(.down))
        let tenth = Int(((clamped - Double(whole)) * 10).rounded(.down))
        return "\(whole / 60):" + String(format: "%02d.%d", whole % 60, tenth)
    }
}
