import Foundation

/// Everything in the editor, written out for a language model to read.
///
/// Written to be small. The model provider counts every token of it against a per-minute budget
/// (8 000 on the free tier, prompt and answer included), so the document is shaped like a compact
/// table rather than a verbose object graph: short references (`c1` for the first clip, `k4` for the
/// fourth caption) instead of 36-character UUIDs, words as `[text, start, end]`, and defaults left
/// out. A one minute talking video comes to roughly two thousand tokens.
///
/// References are positional and resolved back to real ids with `EditPlan.resolvingReferences(in:)`
/// against the same project, which is safe because the studio is locked while the AI is asked.
///
/// Numbers are seconds, rounded to hundredths.
public struct EditDocument: Codable, Sendable, Equatable {
    public static let schema = "cuetake.edit-document/3"

    public var schema: String
    public var title: String
    public var language: String
    /// Seconds of the finished video.
    public var duration: Double
    public var width: Int
    public var height: Int
    public var clips: [Clip]
    public var audio: [Audio]?
    public var style: Style
    /// Captions show only between these finished-video seconds; nil means throughout.
    public var captionWindow: [Double]?
    public var overlays: [OverlayItem]?
    public var voice: Voice
    public var fonts: [String]
    public var animations: [String]
    /// The finished video sampled every `beatStep` seconds, only when asked for.
    public var beats: [Beat]?

    public struct Clip: Codable, Sendable, Equatable {
        /// `c1`, `c2`… in timeline order.
        public var id: String
        public var role: String
        /// Where the clip starts on the finished video, and how long it lasts there.
        public var at: Double
        public var length: Double
        /// Seconds of footage behind it (before speed).
        public var footage: Double
        public var speed: Double?
        public var reversed: Bool?
        public var freeze: Double?
        /// What replaces the background behind the person, when anything does.
        public var background: String?
        public var title: String?
        /// The prompter script, only when there are no words yet.
        public var script: String?
        /// `[text, start, end]` in seconds of this clip's footage. A word's index is its position.
        public var words: [Word]
        /// `[id, text, start, end]` in seconds of this clip's footage.
        public var captions: [Caption]
        /// Other attempts at this clip, when there are any.
        public var takes: [TakeItem]?
    }

    public struct Word: Codable, Sendable, Equatable {
        public var text: String
        public var start: Double
        public var end: Double

        public init(text: String, start: Double, end: Double) {
            self.text = text
            self.start = start
            self.end = end
        }

        public init(from decoder: any Decoder) throws {
            var c = try decoder.unkeyedContainer()
            text = try c.decode(String.self)
            start = try c.decode(Double.self)
            end = try c.decode(Double.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.unkeyedContainer()
            try c.encode(text)
            try c.encode(start)
            try c.encode(end)
        }
    }

    public struct Caption: Codable, Sendable, Equatable {
        public var id: String
        public var text: String
        public var start: Double
        public var end: Double

        public init(id: String, text: String, start: Double, end: Double) {
            self.id = id
            self.text = text
            self.start = start
            self.end = end
        }

        public init(from decoder: any Decoder) throws {
            var c = try decoder.unkeyedContainer()
            id = try c.decode(String.self)
            text = try c.decode(String.self)
            start = try c.decode(Double.self)
            end = try c.decode(Double.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.unkeyedContainer()
            try c.encode(id)
            try c.encode(text)
            try c.encode(start)
            try c.encode(end)
        }
    }

    public struct TakeItem: Codable, Sendable, Equatable {
        public var id: String
        public var length: Double
        public var selected: Bool
        public var text: String
    }

    public struct Audio: Codable, Sendable, Equatable {
        public var id: String
        public var name: String
        public var role: String
        public var at: Double
        public var length: Double
        public var gainDb: Double
        public var fadeIn: Double?
        public var fadeOut: Double?
        public var ducks: Bool?
        public var muted: Bool?
    }

    public struct Style: Codable, Sendable, Equatable {
        public var preset: String
        public var presets: [String]
        /// Text height as a fraction of the frame height (0.018 … 0.075).
        public var size: Double
        public var maxWords: Int
        public var textCase: String
        public var textColor: String
        public var highlightColor: String?
        public var backgroundColor: String?
        public var font: String?
        /// 0 top … 1 bottom.
        public var position: Double
    }

    public struct OverlayItem: Codable, Sendable, Equatable {
        public var id: String
        public var kind: String
        public var text: String?
        public var at: Double
        public var length: Double
        public var x: Double
        public var y: Double
        public var scale: Double
        public var rotation: Double?
        public var opacity: Double?
        public var flipX: Bool?
        public var flipY: Bool?
        public var color: String?
        public var background: String?
        public var font: String?
        public var animation: String
    }

    public struct Voice: Codable, Sendable, Equatable {
        public var noiseReduction: Bool
        public var voiceEnhance: Bool
        public var deRumble: Bool
    }

    /// One moment of the finished video: `t`, the clip's index, the word and caption on screen.
    public struct Beat: Codable, Sendable, Equatable {
        public var t: Double
        public var clip: Int
        public var word: String?
        public var caption: String?
    }
}

/// The short names a document gives to things, and the way back to their real ids.
public struct EditReferences: Sendable {
    public var clips: [String: UUID] = [:]
    public var captions: [String: UUID] = [:]
    public var overlays: [String: UUID] = [:]
    public var audio: [String: UUID] = [:]
    public var takes: [String: UUID] = [:]

    public init(project: Project) {
        var caption = 0
        var take = 0
        for (i, segment) in project.segments.enumerated() {
            clips["c\(i + 1)"] = segment.id
            for cue in segment.captions {
                caption += 1
                captions["k\(caption)"] = cue.id
            }
            if segment.takes.count > 1 {
                for attempt in segment.takes {
                    take += 1
                    takes["t\(take)"] = attempt.id
                }
            }
        }
        for (i, overlay) in project.overlays.enumerated() { overlays["o\(i + 1)"] = overlay.id }
        for (i, clip) in project.audio.enumerated() { audio["a\(i + 1)"] = clip.id }
    }

    /// The real id for whatever the model wrote: a short name, a full id, a unique id prefix, or for
    /// clips a bare number.
    static func resolve(_ reference: String, in table: [String: UUID], numbered prefix: String? = nil) -> String {
        let clean = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = clean.lowercased()
        if let id = table[lower] { return id.uuidString }
        if let prefix, let number = Int(lower), let id = table["\(prefix)\(number)"] { return id.uuidString }
        let ids = Array(table.values)
        if let exact = ids.first(where: { $0.uuidString.lowercased() == lower }) { return exact.uuidString }
        if lower.count >= 6 {
            let matches = ids.filter { $0.uuidString.lowercased().hasPrefix(lower) }
            if matches.count == 1 { return matches[0].uuidString }
        }
        return clean
    }

    public func clip(_ reference: String) -> String { Self.resolve(reference, in: clips, numbered: "c") }
    public func caption(_ reference: String) -> String { Self.resolve(reference, in: captions) }
    public func overlay(_ reference: String) -> String { Self.resolve(reference, in: overlays) }
    public func audioClip(_ reference: String) -> String { Self.resolve(reference, in: audio) }
    public func take(_ reference: String) -> String { Self.resolve(reference, in: takes) }
}

extension EditDocument {
    /// - Parameter beatStep: include a sampled track of the finished video every this many seconds.
    ///   Off by default: it multiplies the size of the document and the words already say the same.
    public init(project: Project, beatStep: Double? = nil) {
        func r2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
        func r3(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }

        var clips: [Clip] = []
        var cursor = 0.0
        var captionNumber = 0
        var takeNumber = 0
        for (index, segment) in project.segments.enumerated() {
            let take = segment.selectedTake
            let words = take?.transcript?.words ?? []
            let playback = segment.playback

            var takes: [TakeItem]?
            if segment.takes.count > 1 {
                takes = segment.takes.map { attempt in
                    takeNumber += 1
                    let text = attempt.transcript?.words.map(\.text).joined(separator: " ") ?? ""
                    return TakeItem(
                        id: "t\(takeNumber)",
                        length: r2(attempt.sourceRange.duration.seconds),
                        selected: attempt.id == segment.selectedTakeID,
                        text: String(text.prefix(90))
                    )
                }
            }

            var captions: [Caption] = []
            for cue in segment.captions {
                captionNumber += 1
                captions.append(Caption(
                    id: "k\(captionNumber)",
                    text: cue.text,
                    start: r2(cue.range.start.seconds),
                    end: r2(cue.range.end.seconds)
                ))
            }

            clips.append(
                Clip(
                    id: "c\(index + 1)",
                    role: segment.role.documentName,
                    at: r2(cursor),
                    length: r2(segment.barWeight),
                    footage: r2(segment.sourceSeconds),
                    speed: abs(playback.speed - 1) > 0.001 ? playback.speed : nil,
                    reversed: playback.isReversed ? true : nil,
                    freeze: playback.freeze.map { r2($0.seconds) },
                    background: segment.background?.rawValue,
                    title: segment.title.isEmpty ? nil : segment.title,
                    script: words.isEmpty && !segment.script.isEmpty ? String(segment.script.prefix(400)) : nil,
                    words: words.map { Word(text: $0.text, start: r2($0.range.start.seconds), end: r2($0.range.end.seconds)) },
                    captions: captions,
                    takes: takes
                )
            )
            cursor += segment.barWeight
        }

        var beats: [Beat]?
        if let beatStep, !project.segments.isEmpty {
            let cues = project.captionCues
            var track: [Beat] = []
            let step = max(0.1, beatStep)
            var t = 0.0
            var clipIndex = 0
            var clipStart = 0.0
            while t < cursor, track.count < 5000 {
                while clipIndex < project.segments.count - 1, t >= clipStart + project.segments[clipIndex].barWeight {
                    clipStart += project.segments[clipIndex].barWeight
                    clipIndex += 1
                }
                let segment = project.segments[clipIndex]
                let local = segment.playback.sourceSeconds(forTimeline: t - clipStart)
                let word = segment.selectedTake?.transcript?.words.first {
                    $0.range.start.seconds <= local && local < $0.range.end.seconds
                }
                track.append(Beat(
                    t: r2(t),
                    clip: clipIndex,
                    word: word?.text,
                    caption: cues.first { $0.range.contains(MediaTime(seconds: t)) }?.text
                ))
                t += step
            }
            beats = track
        }

        var audio: [Audio]?
        if !project.audio.isEmpty {
            audio = project.audio.enumerated().map { i, clip in
                Audio(
                    id: "a\(i + 1)",
                    name: clip.name,
                    role: clip.role.rawValue,
                    at: r2(clip.start.seconds),
                    length: r2(clip.timelineDuration.seconds),
                    gainDb: r2(clip.decibels),
                    fadeIn: clip.fadeIn.seconds > 0 ? r2(clip.fadeIn.seconds) : nil,
                    fadeOut: clip.fadeOut.seconds > 0 ? r2(clip.fadeOut.seconds) : nil,
                    ducks: clip.ducksUnderVoice ? true : nil,
                    muted: clip.isMuted ? true : nil
                )
            }
        }

        var overlays: [OverlayItem]?
        if !project.overlays.isEmpty {
            overlays = project.overlays.enumerated().map { i, overlay in
                var text: String?
                var color: String?
                var background: String?
                var font: String?
                if case .text(let content) = overlay.content {
                    text = content.text
                    color = content.color.hex
                    background = content.background?.hex
                    font = content.fontName
                }
                let t = overlay.transform
                return OverlayItem(
                    id: "o\(i + 1)",
                    kind: overlay.isText ? "text" : "image",
                    text: text,
                    at: r2(overlay.start.seconds),
                    length: r2(overlay.duration.seconds),
                    x: r3(t.x),
                    y: r3(t.y),
                    scale: r3(t.scale),
                    rotation: abs(t.rotation) > 0.01 ? r2(t.rotation) : nil,
                    opacity: t.opacity < 0.999 ? r2(t.opacity) : nil,
                    flipX: t.flipX ? true : nil,
                    flipY: t.flipY ? true : nil,
                    color: color,
                    background: background,
                    font: font,
                    animation: overlay.animation.rawValue
                )
            }
        }

        let style = project.captionStyle
        self.init(
            schema: Self.schema,
            title: project.title,
            language: project.localeIdentifier,
            duration: r2(cursor),
            width: project.format.renderSize.width,
            height: project.format.renderSize.height,
            clips: clips,
            audio: audio,
            style: Style(
                preset: style.presetID,
                presets: CaptionStyle.presetIDs,
                size: r3(style.relativeFontSize),
                maxWords: style.maxWordsPerCue,
                textCase: style.textCase.rawValue,
                textColor: style.textColor.hex,
                highlightColor: style.highlightColor?.hex,
                backgroundColor: style.backgroundColor?.hex,
                font: style.fontName,
                position: r2(style.position.y)
            ),
            captionWindow: project.captionWindow.map { [r2($0.start.seconds), r2($0.end.seconds)] },
            overlays: overlays,
            voice: Voice(
                noiseReduction: project.voiceEffects.noiseReduction,
                voiceEnhance: project.voiceEffects.voiceEnhance,
                deRumble: project.voiceEffects.deRumble
            ),
            fonts: OverlayText.fonts,
            animations: OverlayAnimation.allCases.map(\.rawValue),
            beats: beats
        )
    }

    /// Compact JSON for sending.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

extension SegmentRole {
    /// The role as a plain word for documents: hook, intro, point, example, cta, or the custom name.
    public var documentName: String {
        switch self {
        case .hook: "hook"
        case .intro: "intro"
        case .mainPoint: "point"
        case .example: "example"
        case .callToAction: "cta"
        case .custom(let name): name
        }
    }
}
