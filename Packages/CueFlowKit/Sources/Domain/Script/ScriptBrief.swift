import Foundation

/// What the user asks for: "30 second iPhone 17 Reels video".
/// Input to AI script writing and to the `generateScript` workflow step.
public struct ScriptBrief: Hashable, Sendable, Codable {
    /// Nil inside a workflow template: the topic is asked when the workflow runs.
    public var topic: String?
    public var targetDuration: MediaTime
    public var platform: TargetPlatform
    public var tone: String?
    /// Nil means "use the project's language".
    public var localeIdentifier: String?

    public init(
        topic: String?,
        targetDuration: MediaTime,
        platform: TargetPlatform,
        tone: String? = nil,
        localeIdentifier: String? = nil
    ) {
        self.topic = topic
        self.targetDuration = targetDuration
        self.platform = platform
        self.tone = tone
        self.localeIdentifier = localeIdentifier
    }
}

public enum TargetPlatform: String, Hashable, Sendable, Codable, CaseIterable {
    case instagramReels
    case youtubeShorts
    case tiktok
    case youtube
    case generic

    public var defaultFormat: VideoFormat {
        self == .youtube ? .horizontal1080 : .vertical1080
    }
}

/// AI output before it becomes real segments. Streams in partially while generating.
public struct ScriptDraft: Hashable, Sendable, Codable {
    public var title: String
    public var segments: [SegmentDraft]

    public init(title: String, segments: [SegmentDraft]) {
        self.title = title
        self.segments = segments
    }
}

public struct SegmentDraft: Hashable, Sendable, Codable {
    public var role: SegmentRole
    public var title: String
    public var script: String
    public var estimatedDuration: MediaTime?

    public init(role: SegmentRole, title: String, script: String, estimatedDuration: MediaTime? = nil) {
        self.role = role
        self.title = title
        self.script = script
        self.estimatedDuration = estimatedDuration
    }
}
