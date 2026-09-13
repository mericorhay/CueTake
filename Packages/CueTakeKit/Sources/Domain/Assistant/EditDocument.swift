import Foundation

/// Everything in the editor, written out for a language model to read.
///
/// The model cannot see the timeline, so it gets the timeline as text — in the units a person
/// editing would think in: clips in order with their start and length on the finished video,
/// every word with when it is said, every pause, every caption, the music, the look. And a
/// frame-by-frame track (`beats`) at a fixed step, so a question like "what is on screen at 12.4
/// seconds" has an answer in the document rather than one the model has to work out.
///
/// Numbers are seconds, rounded to hundredths: precise enough to cut inside a word, short enough
/// that a two minute video fits comfortably in a large model's context.
public struct EditDocument: Codable, Sendable, Equatable {
    public static let schema = "cuetake.edit-document/2"

    public var schema: String
    public var project: ProjectInfo
    public var clips: [Clip]
    public var audio: [Audio]
    public var captionStyle: Style
    public var voiceCleanup: Voice
    /// Text and pictures over the video.
    public var overlays: [OverlayItem]
    /// Captions show only between these moments of the finished video; nil means throughout.
    public var captionWindow: Window?
    /// What an overlay can use.
    public var overlayOptions: OverlayOptions
    /// The finished video sampled every `project.beatStep` seconds.
    public var beats: [Beat]

    public struct ProjectInfo: Codable, Sendable, Equatable {
        public var title: String
        public var language: String
        public var width: Int
        public var height: Int
        public var fps: Int
        public var duration: Double
        public var beatStep: Double
    }

    public struct Clip: Codable, Sendable, Equatable {
        /// Stable identifier; operations refer to clips by this.
        public var id: String
        public var index: Int
        public var role: String
        public var title: String
        /// Where the clip sits in the finished video.
        public var start: Double
        public var duration: Double
        /// The footage behind it, in seconds of its recording.
        public var sourceIn: Double?
        public var sourceOut: Double?
        public var speed: Double
        public var reversed: Bool
        public var freezeSeconds: Double?
        public var script: String
        public var words: [Word]
        public var pauses: [Pause]
        public var captions: [Caption]
    }

    /// Times are seconds from the start of the clip's own footage (before speed), which is the
    /// unit cut operations use.
    public struct Word: Codable, Sendable, Equatable {
        public var i: Int
        public var text: String
        public var start: Double
        public var end: Double
    }

    public struct Pause: Codable, Sendable, Equatable {
        public var start: Double
        public var end: Double
    }

    public struct Caption: Codable, Sendable, Equatable {
        public var id: String
        public var text: String
        public var start: Double
        public var end: Double
        /// Where the caption shows on the finished video.
        public var videoStart: Double
        public var videoEnd: Double
        public var edited: Bool
    }

    public struct Audio: Codable, Sendable, Equatable {
        public var id: String
        public var name: String
        public var role: String
        public var start: Double
        public var duration: Double
        public var gainDb: Double
        public var fadeIn: Double
        public var fadeOut: Double
        public var ducksUnderVoice: Bool
        public var muted: Bool
    }

    public struct Style: Codable, Sendable, Equatable {
        public var preset: String
        /// 0 top … 1 bottom.
        public var position: Double
        public var available: [String]
        /// Text height as a fraction of the frame height (0.018 … 0.075).
        public var size: Double
        /// Words on screen at once (1 … 8).
        public var maxWords: Int
        /// natural, uppercase or lowercase.
        public var textCase: String
        public var textColor: String
        /// The word being said lights up in this colour; nil when words are not lit.
        public var highlightColor: String?
        /// The plate behind the text; nil for outlined text.
        public var backgroundColor: String?
        public var font: String?
    }

    public struct Window: Codable, Sendable, Equatable {
        public var from: Double
        public var to: Double
    }

    public struct OverlayItem: Codable, Sendable, Equatable {
        public var id: String
        /// text or image.
        public var kind: String
        public var text: String?
        public var start: Double
        public var duration: Double
        public var end: Double
        /// Centre of the overlay, 0…1 from the left and from the top.
        public var x: Double
        public var y: Double
        /// 1 is the default size (0.1 … 4).
        public var scale: Double
        /// Degrees, clockwise.
        public var rotation: Double
        public var opacity: Double
        public var flipX: Bool
        public var flipY: Bool
        public var color: String?
        public var background: String?
        public var font: String?
        public var animation: String
    }

    public struct OverlayOptions: Codable, Sendable, Equatable {
        public var fonts: [String]
        public var animations: [String]
    }

    public struct Voice: Codable, Sendable, Equatable {
        public var noiseReduction: Bool
        public var voiceEnhance: Bool
        public var deRumble: Bool
    }

    /// One moment of the finished video.
    public struct Beat: Codable, Sendable, Equatable {
        public var t: Double
        public var clip: Int?
        /// The word being said, if any.
        public var word: String?
        /// The caption on screen, if any.
        public var caption: String?
        /// Whether music or another sound clip is playing.
        public var music: Bool
        /// Overlays on screen, by id. Nil when there are none.
        public var overlays: [String]?
    }
}

extension EditDocument {
    /// - Parameter beatStep: seconds between beats. A quarter second is fine enough to find any
    ///   word and coarse enough to keep a three minute video under a few thousand entries.
    public init(project: Project, beatStep: Double = 0.25) {
        func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
        func round3(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }

        var clips: [Clip] = []
        var cursor = 0.0
        let captionFrames = Dictionary(project.captionCues.map { ($0.id, $0.range) }, uniquingKeysWith: { a, _ in a })
        for (index, segment) in project.segments.enumerated() {
            let take = segment.selectedTake
            let words = take?.transcript?.words ?? []
            var pauses: [Pause] = []
            for (left, right) in zip(words, words.dropFirst())
            where right.range.start.seconds - left.range.end.seconds >= 0.3 {
                pauses.append(Pause(start: round2(left.range.end.seconds), end: round2(right.range.start.seconds)))
            }

            clips.append(
                Clip(
                    id: segment.id.uuidString,
                    index: index,
                    role: segment.role.documentName,
                    title: segment.title,
                    start: round2(cursor),
                    duration: round2(segment.barWeight),
                    sourceIn: take.map { round2($0.sourceRange.start.seconds) },
                    sourceOut: take.map { round2($0.sourceRange.end.seconds) },
                    speed: segment.playback.speed,
                    reversed: segment.playback.isReversed,
                    freezeSeconds: segment.playback.freeze.map { round2($0.seconds) },
                    script: segment.script,
                    words: words.enumerated().map { i, word in
                        Word(i: i, text: word.text, start: round2(word.range.start.seconds), end: round2(word.range.end.seconds))
                    },
                    pauses: pauses,
                    captions: segment.captions.map {
                        Caption(
                            id: $0.id.uuidString,
                            text: $0.text,
                            start: round2($0.range.start.seconds),
                            end: round2($0.range.end.seconds),
                            videoStart: round2(captionFrames[$0.id]?.start.seconds ?? -1),
                            videoEnd: round2(captionFrames[$0.id]?.end.seconds ?? -1),
                            edited: $0.isUserEdited
                        )
                    }
                )
            )
            cursor += segment.barWeight
        }

        let total = cursor
        let cues = project.captionCues
        var beats: [Beat] = []
        let step = max(0.05, beatStep)
        var t = 0.0
        var clipIndex = 0
        var clipStart = 0.0
        while t < total, beats.count < 20_000 {
            while clipIndex < project.segments.count - 1,
                  t >= clipStart + project.segments[clipIndex].barWeight {
                clipStart += project.segments[clipIndex].barWeight
                clipIndex += 1
            }
            let segment = project.segments[clipIndex]
            // Seconds into the footage: the timeline offset undone by speed.
            let local = segment.playback.sourceSeconds(forTimeline: t - clipStart)
            let word = segment.selectedTake?.transcript?.words.first {
                $0.range.start.seconds <= local && local < $0.range.end.seconds
            }
            let visibleOverlays = project.overlays.filter { $0.isVisible(at: t) }.map(\.id.uuidString)
            let music = project.audio.contains {
                !$0.isMuted && $0.start.seconds <= t && t < $0.start.seconds + $0.timelineDuration.seconds
            }
            beats.append(
                Beat(
                    t: round2(t),
                    clip: clipIndex,
                    word: word?.text,
                    caption: cues.first { $0.range.contains(MediaTime(seconds: t)) }?.text,
                    music: music,
                    overlays: visibleOverlays.isEmpty ? nil : visibleOverlays
                )
            )
            t += step
        }

        self.init(
            schema: Self.schema,
            project: ProjectInfo(
                title: project.title,
                language: project.localeIdentifier,
                width: project.format.renderSize.width,
                height: project.format.renderSize.height,
                fps: project.format.frameRate,
                duration: round2(total),
                beatStep: step
            ),
            clips: clips,
            audio: project.audio.map {
                Audio(
                    id: $0.id.uuidString,
                    name: $0.name,
                    role: $0.role.rawValue,
                    start: round2($0.start.seconds),
                    duration: round2($0.timelineDuration.seconds),
                    gainDb: round2($0.decibels),
                    fadeIn: round2($0.fadeIn.seconds),
                    fadeOut: round2($0.fadeOut.seconds),
                    ducksUnderVoice: $0.ducksUnderVoice,
                    muted: $0.isMuted
                )
            },
            captionStyle: Style(
                preset: project.captionStyle.presetID,
                position: round2(project.captionStyle.position.y),
                available: CaptionStyle.presetIDs,
                size: round3(project.captionStyle.relativeFontSize),
                maxWords: project.captionStyle.maxWordsPerCue,
                textCase: project.captionStyle.textCase.rawValue,
                textColor: project.captionStyle.textColor.hex,
                highlightColor: project.captionStyle.highlightColor?.hex,
                backgroundColor: project.captionStyle.backgroundColor?.hex,
                font: project.captionStyle.fontName
            ),
            voiceCleanup: Voice(
                noiseReduction: project.voiceEffects.noiseReduction,
                voiceEnhance: project.voiceEffects.voiceEnhance,
                deRumble: project.voiceEffects.deRumble
            ),
            overlays: project.overlays.map { Self.item(for: $0) },
            captionWindow: project.captionWindow.map {
                Window(from: round2($0.start.seconds), to: round2($0.end.seconds))
            },
            overlayOptions: OverlayOptions(
                fonts: OverlayText.fonts,
                animations: OverlayAnimation.allCases.map(\.rawValue)
            ),
            beats: beats
        )
    }

    private static func item(for overlay: Overlay) -> OverlayItem {
        func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
        func round3(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }
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
        return OverlayItem(
            id: overlay.id.uuidString,
            kind: overlay.isText ? "text" : "image",
            text: text,
            start: round2(overlay.start.seconds),
            duration: round2(overlay.duration.seconds),
            end: round2(overlay.start.seconds + overlay.duration.seconds),
            x: round3(overlay.transform.x),
            y: round3(overlay.transform.y),
            scale: round3(overlay.transform.scale),
            rotation: round2(overlay.transform.rotation),
            opacity: round2(overlay.transform.opacity),
            flipX: overlay.transform.flipX,
            flipY: overlay.transform.flipY,
            color: color,
            background: background,
            font: font,
            animation: overlay.animation.rawValue
        )
    }

    /// Compact JSON, sorted keys, for sending.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
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
