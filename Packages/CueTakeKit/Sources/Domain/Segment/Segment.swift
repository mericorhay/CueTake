import Foundation

/// The central unit of CueTake. One beat of the video: "Hook", "Intro", "CTA"...
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
    /// Speed, reverse and freeze. Never baked into the take: a take is what the camera recorded,
    /// and everything here is a decision about it that has to stay undoable.
    public var playback: ClipPlayback
    /// Everything behind the person replaced, or nil for the footage as shot.
    public var background: ClipBackground? = nil
    /// Builds 55–56 kept crop targets here, in seconds from the take's start. Read once on open
    /// and moved to the recording (`Recording.reframe`); nothing reads it after that.
    public var smartReframe: [VideoFocusKeyframe] = []
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
        playback: ClipPlayback = .normal,
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
        self.playback = playback
        self.metadata = metadata
    }

    /// Hand-written so projects saved before speed and freeze existed still open. See the same
    /// note on `Project`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(SegmentRole.self, forKey: .role)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        script = try container.decodeIfPresent(String.self, forKey: .script) ?? ""
        estimatedDuration = try container.decodeIfPresent(MediaTime.self, forKey: .estimatedDuration)
        teleprompter = try container.decodeIfPresent(TeleprompterHints.self, forKey: .teleprompter) ?? TeleprompterHints()
        takes = try container.decodeIfPresent([Take].self, forKey: .takes) ?? []
        selectedTakeID = try container.decodeIfPresent(Take.ID.self, forKey: .selectedTakeID)
        captions = try container.decodeIfPresent([CaptionCue].self, forKey: .captions) ?? []
        playback = try container.decodeIfPresent(ClipPlayback.self, forKey: .playback) ?? .normal
        background = try? container.decodeIfPresent(ClipBackground.self, forKey: .background)
        smartReframe = try container.decodeIfPresent([VideoFocusKeyframe].self, forKey: .smartReframe) ?? []
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
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

extension SegmentRole {
    /// Uppercase label shown by the prompter, blueprint and timeline: HOOK, INTRO, POINT, CTA.
    public var displayLabel: String {
        switch self {
        case .hook: "HOOK"
        case .intro: "INTRO"
        case .mainPoint: "POINT"
        case .example: "EXAMPLE"
        case .callToAction: "CTA"
        case .custom(let name): name.uppercased()
        }
    }
}

extension Segment {
    /// A copy under a new identity.
    ///
    /// Splitting and duplicating both need one, and `id` is `let` on purpose: two segments sharing
    /// an identity would make the timeline, the inspector and SwiftUI's own diffing disagree about
    /// which one is which, in ways that look like random state corruption.
    public func copyWithNewIdentity() -> Segment {
        var copy = Segment(
            role: role,
            title: title,
            script: script,
            estimatedDuration: estimatedDuration,
            teleprompter: teleprompter,
            takes: takes,
            selectedTakeID: selectedTakeID,
            captions: captions,
            playback: playback,
            metadata: metadata
        )
        copy.background = background
        return copy
    }

    /// Length used wherever a segment has to be drawn to scale — the blueprint bar, the studio
    /// progress pips, the editor timeline — before a recording exists to measure.
    ///
    /// Public because every feature lays segments out proportionally, not just one of them.
    public var barWeight: Double {
        playback.timelineSeconds(forSource: sourceSeconds)
    }

    /// How much footage this segment plays, before speed and freeze have their say.
    ///
    /// The take wins over the estimate wherever there is one. The estimate is a guess made from
    /// the script before anything was shot; once there is footage, the guess is the wrong answer
    /// and keeping it is why a trimmed clip used to keep its old width on the timeline.
    public var sourceSeconds: Double {
        (actualDuration ?? estimatedDuration ?? MediaTime(seconds: 5)).seconds
    }
}
