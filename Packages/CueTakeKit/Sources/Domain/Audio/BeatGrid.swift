import Foundation

/// Where a piece of music's beats fall, in the music file's own seconds.
///
/// Found once on the phone (`BeatDetector`) and kept with the clip, so trimming or moving the
/// music never needs the file read again: the beats move with it.
public struct BeatGrid: Hashable, Sendable, Codable {
    public var bpm: Double
    public var beats: [Double]
    /// The first beat of each bar, the strongest pulse: where a cut or a zoom hits hardest.
    public var downbeats: [Double]

    public init(bpm: Double, beats: [Double], downbeats: [Double]) {
        self.bpm = bpm
        self.beats = beats
        self.downbeats = downbeats
    }
}

public struct BeatSyncOptions: Hashable, Sendable, Codable {
    public enum Pulse: String, Hashable, Sendable, Codable, CaseIterable {
        /// Every bar's first beat.
        case bar
        /// Every other bar: calmer.
        case twoBars
        /// Every beat, kept at least `minimumGap` apart: the most energetic.
        case beat
    }

    public var pulse: Pulse
    /// Added magnification of each punch, 0.04…0.35.
    public var amount: Double

    public init(pulse: Pulse = .bar, amount: Double = 0.12) {
        self.pulse = pulse
        self.amount = amount
    }

    private enum CodingKeys: String, CodingKey { case pulse, amount }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pulse = c.value(.pulse, or: .bar)
        amount = c.value(.amount, or: 0.12)
    }
}

extension Project {
    /// The music's beats on the finished video, in time order: `downbeats` only, or every beat.
    public func musicBeats(downbeats: Bool) -> [Double] {
        var times: [Double] = []
        for clip in audio where clip.role == .music && !clip.isMuted {
            guard let grid = clip.beats else { continue }
            let source = clip.sourceRange
            for beat in downbeats ? grid.downbeats : grid.beats {
                guard beat >= source.start.seconds, beat < source.end.seconds else { continue }
                times.append(clip.start.seconds + (beat - source.start.seconds) / max(clip.speed, 0.1))
            }
        }
        return times.sorted()
    }

    public var musicNeedsBeats: Bool {
        audio.contains { $0.role == .music && !$0.isMuted && $0.beats == nil }
    }

    public var hasMusic: Bool {
        audio.contains { $0.role == .music && !$0.isMuted }
    }
}

public enum BeatSync {
    /// The least time between two punches, whatever the music does.
    static let minimumGap = 1.2

    /// Punch-ins on the music's pulse, each inside one clip and short enough to land on the beat
    /// and let go before the next.
    public static func plan(_ options: BeatSyncOptions, project: Project, document: EditDocument) -> [EditPlan.Operation] {
        var pulses = project.musicBeats(downbeats: options.pulse != .beat)
        if options.pulse == .twoBars {
            pulses = pulses.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        }
        let amount = min(max(options.amount, 0.04), 0.35)
        var moves: [EditPlan.Operation] = []
        var last = -Double.infinity
        for time in pulses where time - last >= minimumGap {
            guard let clip = document.clips.first(where: { time >= $0.at && time < $0.at + $0.length }) else { continue }
            let to = min(time + 0.6, clip.at + clip.length - 0.05)
            guard to - time >= 0.3 else { continue }
            moves.append(.cameraMove(CameraMoveRequest(at: time, to: to, kind: .punch, amount: amount, feel: .energetic)))
            last = time
        }
        return moves
    }
}
