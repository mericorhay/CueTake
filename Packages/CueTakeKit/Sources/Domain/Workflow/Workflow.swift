import Foundation

/// A reusable, user-defined recipe such as "My Reels workflow".
///
/// Deliberately a linear list of steps, not a node graph. It is plain Codable data with a schema
/// version, so it can be stored locally, synced, shared, or fetched from an API later.
/// Execution lives in WorkflowEngine; this type knows nothing about how steps run.
public struct WorkflowDefinition: Identifiable, Hashable, Sendable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public let id: UUID
    public var name: String
    public var summary: String?
    public var origin: WorkflowOrigin
    public var steps: [WorkflowStep]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        summary: String? = nil,
        origin: WorkflowOrigin = .user,
        steps: [WorkflowStep],
        createdAt: Date = .now
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.name = name
        self.summary = summary
        self.origin = origin
        self.steps = steps
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

public enum WorkflowOrigin: String, Hashable, Sendable, Codable {
    case builtIn
    case user
    /// Downloaded or generated remotely (API, AI).
    case remote
}

public struct WorkflowStep: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var kind: WorkflowStepKind
    public var isEnabled: Bool

    public init(id: UUID = UUID(), kind: WorkflowStepKind, isEnabled: Bool = true) {
        self.id = id
        self.kind = kind
        self.isEnabled = isEnabled
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
/// app version or an API does not break older clients. Adding a step = adding a case.
public enum WorkflowStepKind: Hashable, Sendable {
    case generateScript(ScriptBrief)
    case segmentScript
    case record(RecordStepOptions)
    case analyzeSpeech
    case generateCaptions
    case applyCaptionStyle(presetID: String)
    case export(ExportPreset)
    case unsupported(type: String)

    /// Steps the runner cannot finish alone; it pauses and hands control to the UI.
    public var requiresUser: Bool {
        switch self {
        case .record: true
        case .generateScript, .segmentScript, .analyzeSpeech, .generateCaptions,
             .applyCaptionStyle, .export, .unsupported: false
        }
    }

    public var typeName: String {
        switch self {
        case .generateScript: StepType.generateScript.rawValue
        case .segmentScript: StepType.segmentScript.rawValue
        case .record: StepType.record.rawValue
        case .analyzeSpeech: StepType.analyzeSpeech.rawValue
        case .generateCaptions: StepType.generateCaptions.rawValue
        case .applyCaptionStyle: StepType.applyCaptionStyle.rawValue
        case .export: StepType.export.rawValue
        case .unsupported(let type): type
        }
    }

    private enum StepType: String {
        case generateScript, segmentScript, record, analyzeSpeech, generateCaptions, applyCaptionStyle, export
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
        switch StepType(rawValue: type) {
        case .generateScript:
            self = .generateScript(try container.decode(ScriptBrief.self, forKey: .parameters))
        case .segmentScript:
            self = .segmentScript
        case .record:
            self = .record(try container.decode(RecordStepOptions.self, forKey: .parameters))
        case .analyzeSpeech:
            self = .analyzeSpeech
        case .generateCaptions:
            self = .generateCaptions
        case .applyCaptionStyle:
            self = .applyCaptionStyle(presetID: try container.decode(CaptionStyleParameters.self, forKey: .parameters).presetID)
        case .export:
            self = .export(try container.decode(ExportPreset.self, forKey: .parameters))
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
        case .record(let options):
            try container.encode(options, forKey: .parameters)
        case .applyCaptionStyle(let presetID):
            try container.encode(CaptionStyleParameters(presetID: presetID), forKey: .parameters)
        case .export(let preset):
            try container.encode(preset, forKey: .parameters)
        case .segmentScript, .analyzeSpeech, .generateCaptions, .unsupported:
            break
        }
    }
}
