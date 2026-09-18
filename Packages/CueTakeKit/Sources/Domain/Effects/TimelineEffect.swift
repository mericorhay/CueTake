import Foundation

/// A tool laid over a stretch of the finished video, from one moment to another.
///
/// Clip settings used to be the only way to apply a look: choosing a background changed the whole
/// clip, and "everywhere" changed every clip, so there was no way to say "blur the room for these
/// four seconds". An effect is pinned to the timeline like a text or a song — it has a start and a
/// length of its own, sits in a lane of its own, and is moved and stretched with a finger.
public struct TimelineEffect: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    /// On the finished video.
    public var start: MediaTime
    public var duration: MediaTime
    public var kind: Kind

    public enum Kind: Hashable, Sendable, Codable {
        /// Everything behind the person replaced.
        case background(BackgroundSettings)
        /// A colour look over the picture.
        case filter(FilterSettings)
        /// A treatment of the voice in the footage.
        case sound(SoundSettings)
    }

    public init(id: UUID = UUID(), start: MediaTime, duration: MediaTime, kind: Kind) {
        self.id = id
        self.start = start
        self.duration = duration
        self.kind = kind
    }

    /// The shortest an effect can be: shorter than this is a flicker nobody chose.
    public static let minimumLength = 0.3

    public var end: Double { start.seconds + duration.seconds }

    public var background: BackgroundSettings? {
        if case .background(let settings) = kind { settings } else { nil }
    }

    public var filter: FilterSettings? {
        if case .filter(let settings) = kind { settings } else { nil }
    }

    public var sound: SoundSettings? {
        if case .sound(let settings) = kind { settings } else { nil }
    }

    /// Whether any of it falls between `from` and `to`, on the finished video.
    public func overlaps(from: Double, to: Double) -> Bool {
        start.seconds < to - 0.001 && end > from + 0.001
    }
}

/// What is kept in front when a background is replaced.
public enum Cutout: String, Hashable, Sendable, Codable, CaseIterable {
    /// People, found by the device's person segmentation.
    case person
    /// Whatever stands out in front — a pet, a product, a person — found by the device's
    /// foreground mask. Slower than `person`, and for anything that is not a person.
    case subject
    /// Everything but one colour: a green or blue screen (see `key`).
    case color
}

/// A point on the picture, 0…1 from the left and from the top.
public struct SubjectPoint: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }

    /// To a hundredth: a tap that lands a pixel away is the same choice.
    var token: String { "p\(Int((x * 100).rounded()))x\(Int((y * 100).rounded()))" }
}

/// How a background is replaced.
public struct BackgroundSettings: Hashable, Sendable, Codable {
    public var style: ClipBackground
    /// What stays in front. People unless chosen otherwise.
    public var cutout: Cutout
    /// The colour taken out, for `.color`.
    public var key: ChromaKey?
    /// For `.subject`, the one thing tapped on: 0…1 from the left and from the top of the first
    /// frame. The render follows it from frame to frame. Nil keeps everything in front.
    public var subjectPoint: SubjectPoint?
    /// 0…1. For blur, how far out of focus the room goes; for dim, how dark it gets.
    public var strength: Double
    /// 0…1. How soft the edge around the person is — hair and shoulders look cut out when it is hard.
    public var feather: Double
    /// The colour behind the person, for `.color`.
    public var color: RGBAColor?
    /// Finer edges, at the cost of a slower render and a warmer phone.
    public var fineEdges: Bool

    public init(
        style: ClipBackground,
        strength: Double = 0.5,
        feather: Double = 0.35,
        color: RGBAColor? = nil,
        fineEdges: Bool = false,
        cutout: Cutout = .person,
        key: ChromaKey? = nil,
        subjectPoint: SubjectPoint? = nil
    ) {
        self.subjectPoint = subjectPoint
        self.style = style
        self.cutout = cutout
        self.key = key
        self.strength = min(max(strength, 0), 1)
        self.feather = min(max(feather, 0), 1)
        self.color = color
        self.fineEdges = fineEdges
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try container.decode(ClipBackground.self, forKey: .style)
        strength = (try? container.decodeIfPresent(Double.self, forKey: .strength)) ?? 0.5
        feather = (try? container.decodeIfPresent(Double.self, forKey: .feather)) ?? 0.35
        color = try? container.decodeIfPresent(RGBAColor.self, forKey: .color)
        fineEdges = (try? container.decodeIfPresent(Bool.self, forKey: .fineEdges)) ?? false
        cutout = (try? container.decodeIfPresent(Cutout.self, forKey: .cutout)) ?? .person
        key = try? container.decodeIfPresent(ChromaKey.self, forKey: .key)
        subjectPoint = try? container.decodeIfPresent(SubjectPoint.self, forKey: .subjectPoint)
    }

    /// The key in use: the chosen one, or a green screen when none was chosen yet.
    public var effectiveKey: ChromaKey { (key ?? .green).clamped }

    /// Whether the edge slider means anything: a keyed colour has its own softness.
    public var usesFeather: Bool { cutout != .color }

    /// Whether the strength slider means anything for this style.
    public var usesStrength: Bool { style == .blur || style == .dim }

    /// Everything that changes the rendered picture, as a file-name-safe string. Two settings with
    /// the same token render the same file.
    public var token: String {
        var parts = [style.token]
        if usesStrength { parts.append("s\(Int((strength * 100).rounded()))") }
        // People are the default and add nothing, so files rendered before there was a choice
        // keep their names.
        switch cutout {
        case .person: break
        case .subject:
            parts.append("subj")
            if let point = subjectPoint { parts.append(point.token) }
        case .color: parts.append(effectiveKey.token)
        }
        if usesFeather { parts.append("f\(Int((feather * 100).rounded()))") }
        if style == .color, let color {
            parts.append(String(color.hex.dropFirst()))
        }
        if fineEdges { parts.append("hq") }
        return parts.joined(separator: "_")
    }
}

/// A stretch of one clip and the background it plays with.
public struct ClipStretch: Hashable, Sendable {
    /// Seconds into the clip, on the finished video's clock.
    public var from: Double
    public var to: Double
    public var background: BackgroundSettings?

    public init(from: Double, to: Double, background: BackgroundSettings?) {
        self.from = from
        self.to = to
        self.background = background
    }

    public var length: Double { to - from }
}

extension Project {
    /// Where a clip begins on the finished video.
    public func timelineStart(ofSegmentAt index: Int) -> Double {
        segments.prefix(max(0, min(index, segments.count))).reduce(0) { $0 + $1.barWeight }
    }

    /// The effects that touch a stretch of the finished video, bottom to top.
    public func effects(from: Double, to: Double) -> [TimelineEffect] {
        effects.filter { $0.overlaps(from: from, to: to) }
    }

    /// A clip cut at every edge of the backgrounds laid over it.
    ///
    /// Where effects overlap the one on top (later in `effects`) wins. Edges closer together than a
    /// couple of frames are merged: a sliver that short cannot be seen and costs a whole piece of
    /// composition. A frozen clip holds one frame, so it is one stretch.
    public func stretches(ofSegmentAt index: Int) -> [ClipStretch] {
        pieces(ofSegmentAt: index) { $0.background }.map { ClipStretch(from: $0.from, to: $0.to, background: $0.value) }
    }

    /// A clip cut at every edge of the sound effects laid over it.
    public func soundStretches(ofSegmentAt index: Int) -> [SoundStretch] {
        pieces(ofSegmentAt: index) { $0.sound }.map { SoundStretch(from: $0.from, to: $0.to, sound: $0.value) }
    }

    private func pieces<Value: Hashable>(
        ofSegmentAt index: Int,
        _ value: (TimelineEffect) -> Value?
    ) -> [(from: Double, to: Double, value: Value?)] {
        guard segments.indices.contains(index) else { return [] }
        let segment = segments[index]
        let start = timelineStart(ofSegmentAt: index)
        let length = segment.barWeight
        let touching = effects(from: start, to: start + length).filter { value($0) != nil }
        guard !touching.isEmpty else { return [(0, length, nil)] }

        if segment.playback.freeze != nil {
            // The most-covering effect, so one that holds most of the frozen frame shows.
            let best = touching.max { overlap($0, start, length) < overlap($1, start, length) }
            return [(0, length, best.flatMap(value))]
        }

        var edges: [Double] = [0, length]
        for effect in touching {
            edges.append(min(max(effect.start.seconds - start, 0), length))
            edges.append(min(max(effect.end - start, 0), length))
        }
        edges.sort()
        var merged: [Double] = []
        for edge in edges {
            if let last = merged.last, edge - last < 0.05 {
                // The clip's own end always survives: it is where the next clip starts.
                if edge == length { merged[merged.count - 1] = length }
                continue
            }
            merged.append(edge)
        }
        if merged.count < 2 { merged = [0, length] }

        var result: [(from: Double, to: Double, value: Value?)] = []
        for (from, to) in zip(merged, merged.dropFirst()) {
            let middle = start + (from + to) / 2
            let top = touching.last { $0.start.seconds <= middle && $0.end > middle }.flatMap(value)
            if let last = result.last, last.value == top {
                result[result.count - 1].to = to
            } else {
                result.append((from, to, top))
            }
        }
        return result
    }

    private func overlap(_ effect: TimelineEffect, _ start: Double, _ length: Double) -> Double {
        max(0, min(effect.end, start + length) - max(effect.start.seconds, start))
    }

    /// Every distinct background a clip needs rendered.
    public func backgrounds(ofSegmentAt index: Int) -> [BackgroundSettings] {
        var seen: [BackgroundSettings] = []
        for stretch in stretches(ofSegmentAt: index) {
            if let background = stretch.background, !seen.contains(background) { seen.append(background) }
        }
        return seen
    }

    /// Clip backgrounds from before effects existed, turned into effects over the same clips.
    mutating func adoptClipBackgrounds() {
        var running = 0.0
        for index in segments.indices {
            let length = segments[index].barWeight
            if let style = segments[index].background {
                effects.append(
                    TimelineEffect(
                        start: MediaTime(seconds: running),
                        duration: MediaTime(seconds: length),
                        kind: .background(BackgroundSettings(style: style))
                    )
                )
                segments[index].background = nil
            }
            running += length
        }
    }
}
