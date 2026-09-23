import Foundation

/// A reusable recipe such as "My Reels workflow": the shape of the video, how it should look, and
/// the automatic tools that turn raw footage into it, in order.
///
/// Plain Codable data with a schema version, and deliberately so. A workflow is stored as a JSON
/// file, can be shared as one, and — the reason the format is written for people rather than for
/// the encoder — can be *written* by an AI from a sentence like "cut the pauses, speed the hook up
/// a little, bold captions". Execution lives in the app; this type knows nothing about how steps
/// run.
///
/// Three parts, kept apart on purpose:
/// - `sections` is the structure: a hook, an intro, three points, a call to action, and which clip
///   fills each one.
/// - `style` is the look, chosen separately, because the same structure is reused with different
///   looks far more often than the other way round.
/// - `steps` is the pipeline of automatic tools.
public struct WorkflowDefinition: Identifiable, Hashable, Sendable, Codable {
    /// 2 added sections, style and editing tools; 3 adds variables, conditions and loops. Older
    /// documents still decode because every added field has a default.
    public static let currentSchemaVersion = 3

    public var schemaVersion: Int
    public let id: UUID
    public var name: String
    public var summary: String?
    public var origin: WorkflowOrigin
    public var sections: [WorkflowSection]
    public var style: WorkflowStyle
    /// Values a condition or loop can read. Runtime values supplied by the app are merged over
    /// these defaults when a run starts.
    public var variables: [String: WorkflowValue]
    public var steps: [WorkflowStep]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        summary: String? = nil,
        origin: WorkflowOrigin = .user,
        sections: [WorkflowSection] = [],
        style: WorkflowStyle = WorkflowStyle(),
        variables: [String: WorkflowValue] = [:],
        steps: [WorkflowStep],
        createdAt: Date = .now
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.name = name
        self.summary = summary
        self.origin = origin
        self.sections = sections
        self.style = style
        self.variables = variables
        self.steps = steps
        self.createdAt = createdAt
        self.updatedAt = createdAt
        ensureFinalExport()
    }

    /// Tolerant on purpose. A workflow an AI wrote will leave out ids, dates and anything it did
    /// not think mattered, and rejecting the whole document over a missing timestamp would make
    /// "an AI can write workflows" true only in theory.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedSchema = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        // Reading an older document performs the migration. A document from a newer app keeps its
        // number so saving it never falsely claims the current app fully understood it.
        schemaVersion = max(storedSchema, Self.currentSchemaVersion)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Workflow"
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        origin = try container.decodeIfPresent(WorkflowOrigin.self, forKey: .origin) ?? .user
        // Lossy, element by element: one malformed section or step from a model must cost that
        // element, not the whole workflow. Throwing here is how an assistant could say "I made you
        // a workflow" and no card ever appeared.
        sections = (try? container.decodeIfPresent([Lossy<WorkflowSection>].self, forKey: .sections))?
            .compactMap(\.value) ?? []
        style = (try? container.decodeIfPresent(WorkflowStyle.self, forKey: .style)) ?? WorkflowStyle()
        variables = (try? container.decodeIfPresent([String: WorkflowValue].self, forKey: .variables)) ?? [:]
        steps = (try? container.decodeIfPresent([Lossy<WorkflowStep>].self, forKey: .steps))?
            .compactMap(\.value) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        // Every workflow ends by writing the video, whatever the document said.
        ensureFinalExport()
    }
}

public enum WorkflowOrigin: String, Hashable, Sendable, Codable {
    case builtIn
    case user
    /// Downloaded or generated remotely (API, AI).
    case remote
    /// Written by the on-device model from the user's own words.
    case ai
}

public struct WorkflowStep: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var kind: WorkflowStepKind
    public var isEnabled: Bool
    /// Optional guard and fan-out. Both default to nil, so schema 1 and 2 documents keep their
    /// exact linear behaviour.
    public var when: WorkflowCondition?
    public var forEach: WorkflowForEach?

    public init(
        id: UUID = UUID(),
        kind: WorkflowStepKind,
        isEnabled: Bool = true,
        when: WorkflowCondition? = nil,
        forEach: WorkflowForEach? = nil
    ) {
        self.id = id
        self.kind = kind
        self.isEnabled = isEnabled
        self.when = when
        self.forEach = forEach
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, isEnabled, when, forEach
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        // Either `{"kind": {"type": …}}` or the flatter `{"type": …}` models often write.
        if let nested = try? container.decode(WorkflowStepKind.self, forKey: .kind) {
            kind = nested
        } else {
            kind = try WorkflowStepKind(from: decoder)
        }
        isEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? true
        when = try? container.decodeIfPresent(WorkflowCondition.self, forKey: .when)
        forEach = try? container.decodeIfPresent(WorkflowForEach.self, forKey: .forEach)
    }
}

public struct RecordStepOptions: Hashable, Sendable, Codable {
    public enum Mode: String, Hashable, Sendable, Codable {
        /// Whole script in one take; split into segments by speech alignment.
        case continuous
        /// One take per segment.
        case perSegment
    }

    public var mode: Mode
    public var camera: CameraPosition
    public var countdownSeconds: Int

    public init(mode: Mode = .continuous, camera: CameraPosition = .front, countdownSeconds: Int = 3) {
        self.mode = mode
        self.camera = camera
        self.countdownSeconds = countdownSeconds
    }
}

/// What a step does. Encoded as `{"type": "...", "parameters": {...}}`.
///
/// Unknown types decode as `.unsupported` instead of failing, so a workflow created by a newer
/// app version, an API or an over-imaginative model does not break older clients. Missing
/// parameters decode as the step's defaults for the same reason. Adding a step = adding a case.
public enum WorkflowStepKind: Hashable, Sendable {
    case generateScript(ScriptBrief)
    /// Makes one video per prompt with a video model, on the user's own key, and lays them in.
    case generateVideo(GenerateVideoOptions)
    case segmentScript
    case record(RecordStepOptions)
    /// Lays the chosen clips into the sections, in section order.
    case assembleSections
    case analyzeSpeech
    case trimSilences(TrimSilencesOptions)
    case cutWords(CutWordsOptions)
    case setSpeed(SpeedOptions)
    case cleanAudio(CleanAudioOptions)
    case musicBed(MusicBedOptions)
    case generateCaptions
    case applyCaptionStyle(presetID: String)
    case export(ExportPreset)
    case unsupported(type: String)

    /// Steps the runner cannot finish alone; it pauses and hands control to the UI.
    public var requiresUser: Bool {
        if case .record = self { return true }
        return false
    }

    public var typeName: String {
        switch self {
        case .generateScript: StepType.generateScript.rawValue
        case .generateVideo: StepType.generateVideo.rawValue
        case .segmentScript: StepType.segmentScript.rawValue
        case .record: StepType.record.rawValue
        case .assembleSections: StepType.assembleSections.rawValue
        case .analyzeSpeech: StepType.analyzeSpeech.rawValue
        case .trimSilences: StepType.trimSilences.rawValue
        case .cutWords: StepType.cutWords.rawValue
        case .setSpeed: StepType.setSpeed.rawValue
        case .cleanAudio: StepType.cleanAudio.rawValue
        case .musicBed: StepType.musicBed.rawValue
        case .generateCaptions: StepType.generateCaptions.rawValue
        case .applyCaptionStyle: StepType.applyCaptionStyle.rawValue
        case .export: StepType.export.rawValue
        case .unsupported(let type): type
        }
    }

    enum StepType: String, CaseIterable {
        case generateScript, generateVideo, segmentScript, record, assembleSections, analyzeSpeech, trimSilences,
             cutWords, setSpeed, cleanAudio, musicBed, generateCaptions, applyCaptionStyle, export
    }

    /// Every type name the app understands, in palette order.
    public static var knownTypes: [String] { StepType.allCases.map(\.rawValue) }

    /// The step with its default parameters, by type name. What the palette inserts, and what an
    /// AI's bare `{"type": "trimSilences"}` becomes.
    public static func make(type: String) -> WorkflowStepKind {
        switch StepType(rawValue: type) {
        case .generateScript: .generateScript(.workflowDefault)
        case .generateVideo: .generateVideo(GenerateVideoOptions())
        case .segmentScript: .segmentScript
        case .record: .record(RecordStepOptions())
        case .assembleSections: .assembleSections
        case .analyzeSpeech: .analyzeSpeech
        case .trimSilences: .trimSilences(TrimSilencesOptions())
        case .cutWords: .cutWords(CutWordsOptions())
        case .setSpeed: .setSpeed(SpeedOptions())
        case .cleanAudio: .cleanAudio(CleanAudioOptions())
        case .musicBed: .musicBed(MusicBedOptions())
        case .generateCaptions: .generateCaptions
        case .applyCaptionStyle: .applyCaptionStyle(presetID: "pop")
        case .export: .export(.shortFormVertical)
        case nil: .unsupported(type: type)
        }
    }
}

extension WorkflowStepKind: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case parameters
    }

    private struct CaptionStyleParameters: Codable {
        var presetID: String
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        func parameters<T: Decodable>(_: T.Type) throws -> T? {
            try container.decodeIfPresent(T.self, forKey: .parameters)
        }

        switch StepType(rawValue: type) {
        case .generateScript:
            self = .generateScript(try parameters(ScriptBrief.self) ?? .workflowDefault)
        case .generateVideo:
            self = .generateVideo(((try? parameters(GenerateVideoOptions.self)) ?? nil) ?? GenerateVideoOptions())
        case .segmentScript:
            self = .segmentScript
        case .record:
            self = .record(try parameters(RecordStepOptions.self) ?? RecordStepOptions())
        case .assembleSections:
            self = .assembleSections
        case .analyzeSpeech:
            self = .analyzeSpeech
        case .trimSilences:
            self = .trimSilences(try parameters(TrimSilencesOptions.self) ?? TrimSilencesOptions())
        case .cutWords:
            self = .cutWords(try parameters(CutWordsOptions.self) ?? CutWordsOptions())
        case .setSpeed:
            self = .setSpeed(try parameters(SpeedOptions.self) ?? SpeedOptions())
        case .cleanAudio:
            self = .cleanAudio(try parameters(CleanAudioOptions.self) ?? CleanAudioOptions())
        case .musicBed:
            self = .musicBed(try parameters(MusicBedOptions.self) ?? MusicBedOptions())
        case .generateCaptions:
            self = .generateCaptions
        case .applyCaptionStyle:
            self = .applyCaptionStyle(presetID: try parameters(CaptionStyleParameters.self)?.presetID ?? "pop")
        case .export:
            self = .export(try parameters(ExportPreset.self) ?? .shortFormVertical)
        case nil:
            self = .unsupported(type: type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeName, forKey: .type)
        switch self {
        case .generateScript(let brief):
            try container.encode(brief, forKey: .parameters)
        case .generateVideo(let options):
            try container.encode(options, forKey: .parameters)
        case .record(let options):
            try container.encode(options, forKey: .parameters)
        case .trimSilences(let options):
            try container.encode(options, forKey: .parameters)
        case .cutWords(let options):
            try container.encode(options, forKey: .parameters)
        case .setSpeed(let options):
            try container.encode(options, forKey: .parameters)
        case .cleanAudio(let options):
            try container.encode(options, forKey: .parameters)
        case .musicBed(let options):
            try container.encode(options, forKey: .parameters)
        case .applyCaptionStyle(let presetID):
            try container.encode(CaptionStyleParameters(presetID: presetID), forKey: .parameters)
        case .export(let preset):
            try container.encode(preset, forKey: .parameters)
        case .segmentScript, .assembleSections, .analyzeSpeech, .generateCaptions, .unsupported:
            break
        }
    }
}

extension ScriptBrief {
    /// A brief with no topic: in a template the topic is asked for when the workflow runs.
    public static let workflowDefault = ScriptBrief(
        topic: nil,
        targetDuration: MediaTime(seconds: 30),
        platform: .instagramReels
    )
}

/// Decodes an element or gives nil, so one bad element does not fail an array.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
