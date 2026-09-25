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
    /// Tools laid over stretches of the finished video.
    public var effects: [Effect]?
    /// Videos playing over the main one.
    public var videos: [Video]?
    /// The main video's own level when it is not 1.
    public var mainVolume: Double?
    /// True when a second listener heard the speech and `useTranscript` can switch between them.
    public var twoListeners: Bool?
    public var voice: Voice
    public var fonts: [String]
    public var animations: [String]
    /// The finished video sampled every `beatStep` seconds, only when asked for.
    public var beats: [Beat]?
    /// Camera moves (zooms) on the finished video.
    public var cameraMoves: [CameraMove]?
    /// The video model `generateVideo` will use, when the user has connected one.
    public var videoModel: String?
    /// Earlier requests in this session and what was done, oldest first.
    public var history: [Turn]?
    /// Everything said, in order, as plain text: what the video is about, in one read.
    public var transcript: String?
    /// What the creator asked the AI to remember across videos (`AIMemory`).
    public var memory: [String]?

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
        public var title: String?
        /// The prompter script, only when there are no words yet.
        public var script: String?
        /// `[text, start, end]` in seconds of this clip's footage. A word's index is its position.
        public var words: [Word]
        /// `[id, text, start, end]` in seconds of this clip's footage.
        public var captions: [Caption]
        /// Other attempts at this clip, when there are any.
        public var takes: [TakeItem]?
        /// True when the picture follows the speaker's face.
        public var tracked: Bool?
        /// Finished-video seconds where the followed face was lost.
        public var lost: [Double]?
        /// How this clip hands over to the next one: `"crossfade 0.5"`. Nil is a plain cut.
        public var transition: String?
        /// What the footage shows, seen on the phone: faces, the kind of scene, writing in the
        /// picture. The only sight of the video the model gets.
        public var sees: String?
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
        /// Drawn behind the people in the picture.
        public var behind: Bool? = nil
        /// For a brand template picture: which template, and its lines by slot.
        public var template: String? = nil
        public var texts: [String: String]? = nil
    }

    /// A background (or later another tool) from one moment of the finished video to another.
    public struct Effect: Codable, Sendable, Equatable {
        /// `e1`, `e2`… bottom to top.
        public var id: String
        public var kind: String
        public var style: String?
        public var from: Double
        public var to: Double
        public var strength: Double?
        public var feather: Double?
        public var color: String?
        /// A filter's or sound effect's settings that differ from their defaults.
        public var values: [String: Double]?
        /// For a background, what stays in front when it is not people: `subject` or `screen`.
        public var keep: String? = nil
        /// The screen colour taken out, when `keep` is `screen`.
        public var screen: String? = nil
    }

    /// An added video: `at`/`length` on the finished video, `file` where in its own file it
    /// starts, `x,y,w,h` its place as fractions of the frame (top left), `keys` its motion.
    public struct Video: Codable, Sendable, Equatable {
        public var id: String
        public var name: String
        public var at: Double
        public var length: Double
        public var file: Double
        public var x: Double
        public var y: Double
        public var w: Double
        public var h: Double
        public var opacity: Double?
        public var volume: Double?
        public var muted: Bool?
        public var hidden: Bool?
        public var keys: [[Double]]?
        /// The screen colour taken out of it, for footage shot on a green or blue screen.
        public var screen: String? = nil
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
    public var effects: [String: UUID] = [:]
    public var videos: [String: UUID] = [:]
    public var moves: [String: UUID] = [:]

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
        for (i, effect) in project.effects.enumerated() { effects["e\(i + 1)"] = effect.id }
        for (i, layer) in project.videoLayers.enumerated() { videos["v\(i + 1)"] = layer.id }
        for (i, move) in EditDocument.cameraMoves(in: project).enumerated() { moves["m\(i + 1)"] = move.recipe.id }
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
    public func effect(_ reference: String) -> String { Self.resolve(reference, in: effects) }
    public func video(_ reference: String) -> String { Self.resolve(reference, in: videos) }
    public func move(_ reference: String) -> String { Self.resolve(reference, in: moves) }
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
                    freeze: nil,
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
                    animation: overlay.animation.rawValue,
                    behind: overlay.isBehindPerson ? true : nil,
                    template: overlay.template?.id,
                    texts: overlay.template?.texts
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
            effects: project.effects.isEmpty ? nil : project.effects.enumerated().map { i, effect in
                let settings = effect.background
                let kind = effect.filter != nil ? "filter" : (effect.sound != nil ? "sound" : "background")
                return Effect(
                    id: "e\(i + 1)",
                    kind: kind,
                    style: settings?.style.rawValue ?? effect.filter?.look.rawValue ?? effect.sound?.preset.rawValue,
                    from: r2(effect.start.seconds),
                    to: r2(effect.end),
                    strength: settings.flatMap { $0.usesStrength ? r2($0.strength) : nil },
                    feather: settings.map { r2($0.feather) },
                    color: settings?.color?.hex,
                    values: Self.values(of: effect),
                    keep: settings.flatMap { Self.keep($0.cutout) },
                    screen: settings.flatMap { $0.cutout == .color ? $0.effectiveKey.color.hex : nil }
                )
            },
            videos: project.videoLayers.isEmpty ? nil : project.videoLayers.enumerated().map { i, layer in
                Video(
                    id: "v\(i + 1)",
                    name: String(layer.title.prefix(30)),
                    at: r2(layer.start.seconds),
                    length: r2(layer.duration),
                    file: r2(layer.sourceRange.start.seconds),
                    x: r2(layer.placement.x),
                    y: r2(layer.placement.y),
                    w: r2(layer.placement.width),
                    h: r2(layer.placement.height),
                    opacity: layer.placement.opacity < 0.999 ? r2(layer.placement.opacity) : nil,
                    volume: layer.volume < 0.999 ? r2(layer.volume) : nil,
                    muted: layer.isMuted ? true : nil,
                    hidden: layer.isHidden ? true : nil,
                    // [at on the finished video, x, y, w, h]
                    keys: layer.keyframes.isEmpty ? nil : layer.orderedKeyframes.map {
                        [r2(layer.start.seconds + $0.time), r2($0.placement.x), r2($0.placement.y), r2($0.placement.width), r2($0.placement.height)]
                    },
                    screen: layer.chroma?.color.hex
                )
            },
            mainVolume: project.mainVideoVolume < 0.999 ? r2(project.mainVideoVolume) : nil,
            twoListeners: project.recordings.contains { $0.speech?.hasCloud == true } ? true : nil,
            voice: Voice(
                noiseReduction: project.voiceEffects.noiseReduction,
                voiceEnhance: project.voiceEffects.voiceEnhance,
                deRumble: project.voiceEffects.deRumble
            ),
            fonts: OverlayText.fonts,
            animations: OverlayAnimation.allCases.map(\.rawValue),
            beats: beats
        )
        history = Self.history(of: project)
        let said = clips.flatMap { $0.words.map(\.text) }.joined(separator: " ")
        transcript = said.isEmpty ? nil : String(said.prefix(1600))
        let moves = Self.cameraMoves(in: project)
        if !moves.isEmpty {
            cameraMoves = moves.enumerated().map { i, move in
                CameraMove(
                    id: "m\(i + 1)",
                    at: r2(move.at),
                    length: r2(move.length),
                    kind: Self.documentName(move.kind),
                    amount: r2(move.recipe.amount),
                    feel: move.kind == .hold || move.recipe.feel == .natural ? nil : move.recipe.feel.rawValue
                )
            }
        }
        for (index, segment) in project.segments.enumerated() where index < self.clips.count {
            if let transition = project.transition(after: segment.id), index < project.segments.count - 1 {
                self.clips[index].transition = "\(transition.kind.rawValue) \(r2(transition.duration))"
            }
        }
        var clipStart = 0.0
        for (index, segment) in project.segments.enumerated() where index < self.clips.count {
            if let track = Self.trackSummary(of: segment, in: project, at: clipStart) {
                self.clips[index].tracked = track.tracked
                self.clips[index].lost = track.lost.isEmpty ? nil : track.lost
            }
            clipStart += segment.barWeight
        }
    }

    /// What stays in front of a background, as the model reads it; people say nothing.
    static func keep(_ cutout: Cutout) -> String? {
        switch cutout {
        case .person: nil
        case .subject: "subject"
        case .color: "screen"
        }
    }

    /// A filter's or sound effect's settings, only those that are not their defaults.
    static func values(of effect: TimelineEffect) -> [String: Double]? {
        var values: [String: Double] = [:]
        func put(_ key: String, _ value: Double, unless fallback: Double) {
            if abs(value - fallback) > 0.001 { values[key] = (value * 100).rounded() / 100 }
        }
        if let filter = effect.filter {
            put("intensity", filter.intensity, unless: 1)
            put("brightness", filter.brightness, unless: 0)
            put("contrast", filter.contrast, unless: 0)
            put("saturation", filter.saturation, unless: 0)
            put("warmth", filter.warmth, unless: 0)
            put("vignette", filter.vignette, unless: 0)
            put("sharpness", filter.sharpness, unless: 0)
        } else if let sound = effect.sound {
            put("amount", sound.amount, unless: 0.7)
            put("pitch", sound.pitch, unless: SoundSettings.defaultPitch(for: sound.preset))
            put("volume", sound.volume, unless: 0)
        }
        return values.isEmpty ? nil : values
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

    /// The closed vocabulary exposed to the editor AI. Custom labels stay a user-facing choice;
    /// accepting arbitrary model text here would silently create unusable workflow roles.
    public init?(documentName: String) {
        switch documentName.lowercased() {
        case "hook": self = .hook
        case "intro": self = .intro
        case "point": self = .mainPoint
        case "example": self = .example
        case "cta": self = .callToAction
        default: return nil
        }
    }
}
