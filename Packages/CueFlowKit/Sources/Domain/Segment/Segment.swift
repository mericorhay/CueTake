import Foundation

/// The central unit of CueFlow. One beat of the video: "Hook", "Intro", "CTA"...
///
/// A segment stores only what is intrinsic to it. Its position in the final video
/// (start / end on the timeline) is *derived* by `TimelineBuilder`, never stored,
/// so retaking one segment never forces the others to shift.
public struct Segment: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var role: SegmentRole
    public var title: String
    /// What the teleprompter shows and what speech tracking aligns against.
    public var script: String
    /// Hint from AI or the user. When nil, it is estimated from the script (see `estimatedSpeakingDuration`).
    public var estimatedDuration: MediaTime?
    public var teleprompter: TeleprompterHints
    /// Every attempt at this segment, oldest first. Retakes append here.
    public var takes: [Take]
    public var selectedTakeID: Take.ID?
    /// Captions for the selected take. Times are relative to the start of the segment.
    public var captions: [CaptionCue]
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        role: SegmentRole,
        title: String = "",
        script: String,
        estimatedDuration: MediaTime? = nil,
        teleprompter: TeleprompterHints = TeleprompterHints(),
        takes: [Take] = [],
        selectedTakeID: Take.ID? = nil,
        captions: [CaptionCue] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.role = role
        self.title = title
        self.script = script
        self.estimatedDuration = estimatedDuration
        self.teleprompter = teleprompter
        self.takes = takes
        self.selectedTakeID = selectedTakeID
        self.captions = captions
        self.metadata = metadata
    }

    public init(draft: SegmentDraft) {
        self.init(role: draft.role, title: draft.title, script: draft.script, estimatedDuration: draft.estimatedDuration)
    }

    public var selectedTake: Take? {
        guard let selectedTakeID else { return nil }
        return takes.first { $0.id == selectedTakeID }
    }

    /// Derived, so it can never disagree with the takes.
    public var recordingState: SegmentRecordingState {
        guard let take = selectedTake else { return .notRecorded }
        switch take.status {
        case .recording: return .recording
        case .processing: return .processing
        case .ready: return .ready
        case .failed: return .failed
        }
    }

    public var actualDuration: MediaTime? { selectedTake?.duration }

    public func estimatedSpeakingDuration(wordsPerMinute: Double) -> MediaTime {
        if let estimatedDuration { return estimatedDuration }
        let words = ScriptText.words(in: script).count
        return MediaTime(seconds: Double(words) / wordsPerMinute * 60)
    }
}

public enum SegmentRole: Hashable, Sendable, Codable {
    case hook
    case intro
    case mainPoint
    case example
    case callToAction
    case custom(String)
}

public enum SegmentRecordingState: Hashable, Sendable {
    case notRecorded
    case recording
    case processing
    case ready
    case failed
}

/// Per-segment teleprompter preferences. Device-level preferences (mirroring, font size) live in settings.
public struct TeleprompterHints: Hashable, Sendable, Codable {
    /// Multiplier for fixed-speed scrolling, relative to the user's base speed.
    public var speedMultiplier: Double
    /// Private notes shown to the speaker, never in the video.
    public var speakerNotes: String?

    public init(speedMultiplier: Double = 1, speakerNotes: String? = nil) {
        self.speedMultiplier = speedMultiplier
        self.speakerNotes = speakerNotes
    }
}
