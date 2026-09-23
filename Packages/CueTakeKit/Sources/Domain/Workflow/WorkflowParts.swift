import Foundation

// MARK: - Structure

/// One beat of the video's structure: a hook, an intro, a point.
///
/// The role is a plain string rather than `SegmentRole`, because this is the part of the document
/// people and models write by hand, and `{"role": "hook"}` is something anyone can write where the
/// synthesised encoding of an enum with a payload is not.
public struct WorkflowSection: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    /// `hook`, `intro`, `point`, `example`, `cta`, or any other name, which is kept as it is.
    public var role: String
    public var title: String
    /// How long this beat should run, as a target.
    public var seconds: Double
    /// Which of the chosen clips fills this section, counting from 1. Nil until someone — the
    /// user by dragging, or an AI by writing a number — decides.
    public var clip: Int?

    public init(id: UUID = UUID(), role: String, title: String = "", seconds: Double = 5, clip: Int? = nil) {
        self.id = id
        self.role = role
        self.title = title
        self.seconds = seconds
        self.clip = clip
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, title, seconds, clip
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "point"
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        seconds = (try? container.decodeIfPresent(Double.self, forKey: .seconds))
            ?? (try? container.decodeIfPresent(String.self, forKey: .seconds)).flatMap { Double($0) }
            ?? 5
        clip = try? container.decodeIfPresent(Int.self, forKey: .clip)
    }

    /// The segment role this section becomes.
    public var segmentRole: SegmentRole {
        switch role.lowercased() {
        case "hook": .hook
        case "intro": .intro
        case "point", "mainpoint": .mainPoint
        case "example": .example
        case "cta", "calltoaction": .callToAction
        default: .custom(role)
        }
    }

    public static let standardRoles = ["hook", "intro", "point", "example", "cta"]
}

// MARK: - Style

/// How the finished video looks, chosen apart from its structure.
public struct WorkflowStyle: Hashable, Sendable, Codable {
    public var captions: Bool
    /// One of `CaptionStyle.presetIDs`.
    public var captionPreset: String
    /// `top`, `middle` or `bottom`.
    public var captionPosition: String
    public var aspect: VideoFormat.AspectRatio
    public var resolution: VideoFormat.Resolution
    public var frameRate: Int

    public init(
        captions: Bool = true,
        captionPreset: String = "pop",
        captionPosition: String = "bottom",
        aspect: VideoFormat.AspectRatio = .portrait9x16,
        resolution: VideoFormat.Resolution = .hd1080,
        frameRate: Int = 30
    ) {
        self.captions = captions
        self.captionPreset = captionPreset
        self.captionPosition = captionPosition
        self.aspect = aspect
        self.resolution = resolution
        self.frameRate = frameRate
    }

    private enum CodingKeys: String, CodingKey {
        case captions, captionPreset, captionPosition, aspect, resolution, frameRate
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = WorkflowStyle()
        captions = try c.decodeIfPresent(Bool.self, forKey: .captions) ?? fallback.captions
        captionPreset = try c.decodeIfPresent(String.self, forKey: .captionPreset) ?? fallback.captionPreset
        captionPosition = try c.decodeIfPresent(String.self, forKey: .captionPosition) ?? fallback.captionPosition
        // `try?` on the enums: a model that writes "vertical" instead of "portrait9x16" should get
        // the default, not a failed document.
        aspect = (try? c.decodeIfPresent(VideoFormat.AspectRatio.self, forKey: .aspect)) ?? fallback.aspect
        resolution = (try? c.decodeIfPresent(VideoFormat.Resolution.self, forKey: .resolution)) ?? fallback.resolution
        frameRate = try c.decodeIfPresent(Int.self, forKey: .frameRate) ?? fallback.frameRate
    }

    public var format: VideoFormat {
        VideoFormat(aspectRatio: aspect, resolution: resolution, frameRate: frameRate).deliveryCompatible
    }

    public var position: CaptionPosition {
        switch captionPosition.lowercased() {
        case "top": CaptionPosition(x: 0.5, y: 0.2)
        case "middle", "center": .center
        default: .lowerThird
        }
    }
}

// MARK: - Step options

public struct TrimSilencesOptions: Hashable, Sendable, Codable {
    /// Pauses longer than this are cut, in seconds.
    public var minPause: Double
    /// Air kept either side of every phrase, in seconds.
    public var padding: Double

    public init(minPause: Double = 0.6, padding: Double = 0.12) {
        self.minPause = minPause
        self.padding = padding
    }

    private enum CodingKeys: String, CodingKey { case minPause, padding }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minPause = try c.decodeIfPresent(Double.self, forKey: .minPause) ?? 0.6
        padding = try c.decodeIfPresent(Double.self, forKey: .padding) ?? 0.12
    }
}

public struct CutWordsOptions: Hashable, Sendable, Codable {
    /// Words removed wherever they are said on their own. Compared case- and accent-insensitively.
    public var words: [String]

    public init(words: [String] = ["ee", "eee", "ıı", "ııı", "hmm", "um", "uh", "yani"]) {
        self.words = words
    }

    private enum CodingKeys: String, CodingKey { case words }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        words = try c.decodeIfPresent([String].self, forKey: .words) ?? CutWordsOptions().words
    }
}

public struct SpeedOptions: Hashable, Sendable, Codable {
    /// `all`, or a section role such as `hook`.
    public var target: String
    public var speed: Double

    public init(target: String = "all", speed: Double = 1.1) {
        self.target = target
        self.speed = speed
    }

    private enum CodingKeys: String, CodingKey { case target, speed }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        target = try c.decodeIfPresent(String.self, forKey: .target) ?? "all"
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1.1
    }
}

public struct CleanAudioOptions: Hashable, Sendable, Codable {
    public var denoise: Bool
    public var enhanceVoice: Bool
    public var removeRumble: Bool

    public init(denoise: Bool = true, enhanceVoice: Bool = true, removeRumble: Bool = true) {
        self.denoise = denoise
        self.enhanceVoice = enhanceVoice
        self.removeRumble = removeRumble
    }

    private enum CodingKeys: String, CodingKey { case denoise, enhanceVoice, removeRumble }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        denoise = try c.decodeIfPresent(Bool.self, forKey: .denoise) ?? true
        enhanceVoice = try c.decodeIfPresent(Bool.self, forKey: .enhanceVoice) ?? true
        removeRumble = try c.decodeIfPresent(Bool.self, forKey: .removeRumble) ?? true
    }
}

public struct MusicBedOptions: Hashable, Sendable, Codable {
    public var levelDB: Double
    public var ducking: Bool
    public var fadeIn: Double
    public var fadeOut: Double

    public init(levelDB: Double = -12, ducking: Bool = true, fadeIn: Double = 0.5, fadeOut: Double = 1.2) {
        self.levelDB = levelDB
        self.ducking = ducking
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
    }

    private enum CodingKeys: String, CodingKey { case levelDB, ducking, fadeIn, fadeOut }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        levelDB = try c.decodeIfPresent(Double.self, forKey: .levelDB) ?? -12
        ducking = try c.decodeIfPresent(Bool.self, forKey: .ducking) ?? true
        fadeIn = try c.decodeIfPresent(Double.self, forKey: .fadeIn) ?? 0.5
        fadeOut = try c.decodeIfPresent(Double.self, forKey: .fadeOut) ?? 1.2
    }
}

// MARK: - Categories

/// Where a tool sits in the palette. Grouped by what it does to the video, the same way the
/// editor's catalogue is, so a tool is found in the same place in both.
public enum WorkflowToolCategory: String, CaseIterable, Hashable, Sendable {
    case structure
    /// Makes footage: video models, later voices and music.
    case generate
    case cut
    case sound
    case words
    /// The picture: filters, backgrounds, camera moves, transitions.
    case look
    /// Titles, brand templates and the brand kit.
    case brand
    case deliver
}

extension WorkflowStepKind {
    public var category: WorkflowToolCategory {
        switch self {
        case .generateScript, .segmentScript, .record, .assembleSections: .structure
        case .generateVideo, .aiEdit: .generate
        case .trimSilences, .cutWords, .setSpeed, .cleanup, .bestTakes: .cut
        case .cleanAudio, .musicBed, .voiceEffect, .soundDesign: .sound
        case .analyzeSpeech, .generateCaptions, .applyCaptionStyle: .words
        case .filter, .background, .autoZoom, .trackFace, .transitions, .videoLayout: .look
        case .addTitle, .brandTemplate, .brandKit, .applyStyle: .brand
        case .export, .unsupported: .deliver
        }
    }
}

// MARK: - JSON

extension WorkflowDefinition {
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// The document as people read it: pretty-printed, sorted, dates as ISO strings.
    public func jsonString() throws -> String {
        String(decoding: try Self.encoder.encode(self), as: UTF8.self)
    }

    /// Reads a document, however it was written.
    ///
    /// Models like to wrap JSON in a code fence and a sentence of preamble; everything outside the
    /// outermost braces is ignored rather than treated as an error.
    public static func decode(json: String) throws -> WorkflowDefinition {
        var text = json
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            text = String(text[start...end])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self),
               let date = ISO8601DateFormatter().date(from: string) {
                return date
            }
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            return .now
        }
        return try decoder.decode(WorkflowDefinition.self, from: Data(text.utf8))
    }

    /// What a model is told about the format.
    ///
    /// Kept next to the types it describes, so adding a step and forgetting to tell the AI about
    /// it are at least in the same file.
    public static let authoringGuide = """
    A CueTake workflow is a JSON object:
    {
      "name": "short name",
      "summary": "one sentence",
      "sections": [ { "role": "hook|intro|point|example|cta", "title": "", "seconds": 5, "clip": 1 } ],
      "style": { "captions": true, "captionPreset": "pop|clean|karaoke|bold|boxed|minimal|neon|story", "captionPosition": "top|middle|bottom",
                 "aspect": "portrait9x16|landscape16x9|square1x1", "resolution": "hd1080|uhd4K", "frameRate": 24|30|60|120 },
      "steps": [ { "kind": { "type": "<type>", "parameters": { } } } ]
    }
    "clip" is which of the user's clips fills the section, counting from 1; leave it out if unknown.
    Use at most 60 fps with uhd4K. hd1080 may use 24, 30, 60 or 120 fps.
    Step types, in the order they usually run:
    - assembleSections: put the clips into the sections.
    - analyzeSpeech: transcribe what is said. Needed before trimSilences, cutWords and captions.
    - trimSilences: { "minPause": 0.6, "padding": 0.12 } cut pauses longer than minPause seconds.
    - cutWords: { "words": ["um", "uh"] } remove filler words.
    - setSpeed: { "target": "all|hook|intro|point|example|cta", "speed": 1.1 } between 0.25 and 4.
    - cleanAudio: { "denoise": true, "enhanceVoice": true, "removeRumble": true }
    - musicBed: { "levelDB": -12, "ducking": true, "fadeIn": 0.5, "fadeOut": 1.2 } level existing music.
    - generateCaptions: build captions from the transcript.
    - applyCaptionStyle: { "presetID": "pop|clean|karaoke|bold|boxed|minimal|neon|story" }
    - export: write the finished video. Always the last step, exactly once; the app adds it if missing.
      { "destination": "photoLibrary|files", "delivery": { "endpoint": "https://…", "method": "POST|PUT", "payload": "multipart|rawVideo|json", "fields": { } } }
      Only add "delivery" when the user asks to send the video to a URL or API. Never invent a URL.
    Only use these types. Answer with the JSON object only.
    """
}

// MARK: - Built-ins

extension WorkflowDefinition {
    /// The workflows a new install starts with. Fixed identifiers, so re-seeding never duplicates
    /// them and a user's edit to one is recognised as an edit to that one.
    public static let builtIns: [WorkflowDefinition] = [
        WorkflowDefinition(
            id: UUID(uuidString: "6B1B3C0E-0F4E-4C59-9E3A-11A0C0DE0001")!,
            name: "Talking head, cleaned up",
            summary: "Pauses and filler words out, captions on.",
            origin: .builtIn,
            sections: [
                WorkflowSection(role: "hook", title: "Hook", seconds: 3, clip: 1),
                WorkflowSection(role: "point", title: "Point", seconds: 15, clip: 2),
                WorkflowSection(role: "cta", title: "CTA", seconds: 4, clip: 3),
            ],
            style: WorkflowStyle(captionPreset: "pop"),
            steps: [
                WorkflowStep(kind: .assembleSections),
                WorkflowStep(kind: .analyzeSpeech),
                WorkflowStep(kind: .trimSilences(TrimSilencesOptions())),
                WorkflowStep(kind: .cutWords(CutWordsOptions())),
                WorkflowStep(kind: .generateCaptions),
                WorkflowStep(kind: .applyCaptionStyle(presetID: "pop")),
            ]
        ),
        WorkflowDefinition(
            id: UUID(uuidString: "6B1B3C0E-0F4E-4C59-9E3A-11A0C0DE0002")!,
            name: "Three-point reel",
            summary: "A fast hook, three points, a call to action.",
            origin: .builtIn,
            sections: [
                WorkflowSection(role: "hook", title: "Hook", seconds: 3),
                WorkflowSection(role: "point", title: "Point 1", seconds: 7),
                WorkflowSection(role: "point", title: "Point 2", seconds: 7),
                WorkflowSection(role: "point", title: "Point 3", seconds: 7),
                WorkflowSection(role: "cta", title: "CTA", seconds: 3),
            ],
            style: WorkflowStyle(captionPreset: "karaoke", captionPosition: "middle", frameRate: 60),
            steps: [
                WorkflowStep(kind: .assembleSections),
                WorkflowStep(kind: .analyzeSpeech),
                WorkflowStep(kind: .trimSilences(TrimSilencesOptions(minPause: 0.45, padding: 0.08))),
                WorkflowStep(kind: .setSpeed(SpeedOptions(target: "hook", speed: 1.15))),
                WorkflowStep(kind: .musicBed(MusicBedOptions())),
                WorkflowStep(kind: .generateCaptions),
                WorkflowStep(kind: .applyCaptionStyle(presetID: "karaoke")),
                WorkflowStep(kind: .export(.shortFormVertical)),
            ]
        ),
    ]
}
