import Foundation

/// A camera move as the model asked for it: a new one over `at`…`to` of the finished video, or
/// changes to an existing one (`move`).
public struct CameraMoveRequest: Hashable, Sendable {
    public var move: String?
    public var at: Double?
    public var to: Double?
    public var kind: CameraMotionRecipe.Kind?
    /// Added magnification, 0.02…0.8.
    public var amount: Double?
    public var feel: CameraMotionRecipe.Feel?

    public init(
        move: String? = nil,
        at: Double? = nil,
        to: Double? = nil,
        kind: CameraMotionRecipe.Kind? = nil,
        amount: Double? = nil,
        feel: CameraMotionRecipe.Feel? = nil
    ) {
        self.move = move
        self.at = at
        self.to = to
        self.kind = kind
        self.amount = amount
        self.feel = feel
    }

    /// The names models use for the four moves.
    static func kind(_ name: String?) -> CameraMotionRecipe.Kind? {
        switch name?.lowercased().replacingOccurrences(of: "_", with: "") {
        case "push", "pushin", "zoomin", "in": .pushIn
        case "pull", "pullout", "zoomout", "out": .pullOut
        case "punch", "punchin", "snap", "bump": .punch
        case "hold", "static", "crop", "still": .hold
        default: nil
        }
    }

    static func feel(_ name: String?) -> CameraMotionRecipe.Feel? {
        switch name?.lowercased() {
        case "calm", "slow", "smooth", "soft": .calm
        case "natural", "normal": .natural
        case "energetic", "fast", "snappy", "hard": .energetic
        default: nil
        }
    }

    /// 15, 0.15 and "15%" all mean fifteen percent closer.
    static func amount(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        let unit = value > 1.5 ? value / 100 : (value > 1 ? value - 1 : value)
        return min(max(unit, 0.02), 0.8)
    }
}

extension EditDocument {
    /// A camera move on the finished video: `m1`, `m2`… in timeline order.
    public struct CameraMove: Codable, Sendable, Equatable {
        public var id: String
        public var at: Double
        public var length: Double
        /// push, pull, punch or hold.
        public var kind: String
        /// Added magnification: 0.15 is 15% closer at the move's peak.
        public var amount: Double
        public var feel: String?
    }

    static func documentName(_ kind: CameraMotionRecipe.Kind) -> String {
        switch kind {
        case .pushIn: "push"
        case .pullOut: "pull"
        case .punch: "punch"
        case .hold: "hold"
        }
    }

    /// Every camera move as seen on the finished video, in order, with the recipe behind it.
    static func cameraMoves(in project: Project) -> [(recipe: CameraMotionRecipe, at: Double, length: Double, kind: CameraMotionRecipe.Kind)] {
        var result: [(CameraMotionRecipe, Double, Double, CameraMotionRecipe.Kind)] = []
        var seen = Set<UUID>()
        var cursor = 0.0
        for segment in project.segments {
            defer { cursor += segment.barWeight }
            guard let take = segment.selectedTake,
                  let recording = project.recording(id: take.recordingID)
            else { continue }
            let takeStart = take.sourceRange.start.seconds
            let length = take.sourceRange.duration.seconds
            for recipe in (recording.cameraMotions ?? []).sorted(by: { $0.start < $1.start }) where !seen.contains(recipe.id) {
                let lower = max(recipe.start, takeStart), upper = min(recipe.end, takeStart + length)
                guard upper - lower > 0.01,
                      let a = segment.playback.timelineOffset(forSourceOffset: lower - takeStart, sourceLength: length),
                      let b = segment.playback.timelineOffset(forSourceOffset: upper - takeStart, sourceLength: length)
                else { continue }
                seen.insert(recipe.id)
                result.append((
                    recipe,
                    cursor + min(a, b),
                    abs(b - a),
                    recipe.kind.facingTimeline(isReversed: segment.playback.isReversed)
                ))
            }
        }
        return result.sorted { $0.1 < $1.1 }
    }

    /// Finished-video seconds where a clip's tracked subject was lost, or nil when it is not tracked.
    static func trackSummary(of segment: Segment, in project: Project, at cursor: Double) -> (tracked: Bool, lost: [Double])? {
        guard let take = segment.selectedTake,
              let recording = project.recording(id: take.recordingID)
        else { return nil }
        let start = take.sourceRange.start.seconds, end = take.sourceRange.end.seconds
        let points = (recording.reframe ?? []).filter { $0.time >= start - 0.0001 && $0.time <= end + 0.0001 }
        guard points.count >= 2 else { return nil }
        var lost: [Double] = []
        var previousLost = false
        for point in points.sorted(by: { $0.time < $1.time }) {
            let isLost = point.trackingState == .searching
            if isLost, !previousLost,
               let local = segment.playback.timelineOffset(forSourceOffset: point.time - start, sourceLength: end - start) {
                lost.append(((cursor + local) * 100).rounded() / 100)
            }
            previousLost = isLost
        }
        return (true, lost)
    }
}

/// A video the model wants made and laid in.
public struct GenerateClipRequest: Hashable, Sendable {
    public var prompt: String
    /// The moment of the finished video it goes to; nil is the playhead.
    public var at: Double?
    public var seconds: Double?
    /// A clip of its own instead of B-roll over the video.
    public var asClip: Bool
    /// A `VideoModelPreset` id; nil uses the model the user last chose.
    public var model: String?

    public init(prompt: String, at: Double? = nil, seconds: Double? = nil, asClip: Bool = false, model: String? = nil) {
        self.prompt = prompt
        self.at = at
        self.seconds = seconds
        self.asClip = asClip
        self.model = model
    }
}
