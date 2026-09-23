import Foundation

/// A video project. The ordered `segments` array is the backbone of the whole app:
/// teleprompter, speech tracking, recording, captions, timeline and retakes all address segments.
///
/// Persisted as a versioned JSON document next to its media files (see Persistence).
public struct Project: Identifiable, Hashable, Sendable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public let id: UUID
    public var title: String
    public var format: VideoFormat
    /// BCP-47 identifier of the spoken language, e.g. "tr-TR". Drives speech, AI and caption casing.
    public var localeIdentifier: String
    /// Order in this array is the order in the video.
    public var segments: [Segment]
    /// Physical media files. Takes point into these.
    public var recordings: [Recording]
    public var captionStyle: CaptionStyle
    /// Music, voiceover and effects laid over the video. Separate from `segments` because they are
    /// pinned to moments rather than derived from order (see `AudioClip`).
    public var audio: [AudioClip]
    /// Repair for the voice inside the footage: every clip's own sound, not added audio.
    public var voiceEffects: AudioEffects
    /// Pictures and text over the video, bottom to top.
    public var overlays: [Overlay]
    public var videoLayers: [VideoLayer]
    public var mainVideoPlacement: VideoPlacement
    public var mainVideoVolume: Double
    /// When captions are shown, on the finished video. Nil shows them throughout.
    public var captionWindow: MediaTimeRange?
    /// Tools laid over stretches of the finished video, bottom to top (see `TimelineEffect`).
    public var effects: [TimelineEffect]
    public var createdAt: Date
    public var updatedAt: Date
    public var metadata: [String: String]
    /// What the AI was asked and did in this project, session by session.
    public var aiConversations: [AIConversation] = []
    /// How clips hand over to each other (see `ClipTransition`).
    public var transitions: [ClipTransition] = []

    public init(
        id: UUID = UUID(),
        title: String,
        format: VideoFormat = .vertical1080,
        localeIdentifier: String,
        segments: [Segment] = [],
        recordings: [Recording] = [],
        captionStyle: CaptionStyle = .standard,
        audio: [AudioClip] = [],
        createdAt: Date = .now,
        metadata: [String: String] = [:]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.title = title
        self.format = format
        self.localeIdentifier = localeIdentifier
        self.segments = segments
        self.recordings = recordings
        self.captionStyle = captionStyle
        self.audio = audio
        self.voiceEffects = AudioEffects()
        self.overlays = []
        self.videoLayers = []
        self.mainVideoPlacement = .full
        self.mainVideoVolume = 1
        self.captionWindow = nil
        self.effects = []
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.metadata = metadata
    }

    /// Hand-written so documents saved before audio existed still open.
    ///
    /// The synthesised decoder treats every stored property as required, which means the day a
    /// field is added is the day every project already on disk stops loading. `schemaVersion` is
    /// here to make migrations explicit; this is the cheap half of that promise — a missing field
    /// decodes as its default rather than as a failure.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        format = try container.decode(VideoFormat.self, forKey: .format).deliveryCompatible
        localeIdentifier = try container.decode(String.self, forKey: .localeIdentifier)
        segments = try container.decodeIfPresent([Segment].self, forKey: .segments) ?? []
        recordings = try container.decodeIfPresent([Recording].self, forKey: .recordings) ?? []
        captionStyle = try container.decodeIfPresent(CaptionStyle.self, forKey: .captionStyle) ?? .standard
        audio = try container.decodeIfPresent([AudioClip].self, forKey: .audio) ?? []
        voiceEffects = try container.decodeIfPresent(AudioEffects.self, forKey: .voiceEffects) ?? AudioEffects()
        overlays = (try? container.decodeIfPresent([Overlay].self, forKey: .overlays)) ?? []
        videoLayers = try container.decodeIfPresent([VideoLayer].self, forKey: .videoLayers) ?? []
        mainVideoPlacement = try container.decodeIfPresent(VideoPlacement.self, forKey: .mainVideoPlacement) ?? .full
        mainVideoVolume = try container.decodeIfPresent(Double.self, forKey: .mainVideoVolume) ?? 1
        captionWindow = try? container.decodeIfPresent(MediaTimeRange.self, forKey: .captionWindow)
        effects = (try? container.decodeIfPresent([TimelineEffect].self, forKey: .effects)) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
        aiConversations = (try? container.decodeIfPresent([AIConversation].self, forKey: .aiConversations)) ?? []
        transitions = (try? container.decodeIfPresent([ClipTransition].self, forKey: .transitions)) ?? []
        // Backgrounds used to be a setting of the whole clip.
        adoptClipBackgrounds()
        // Freeze is gone from the app: held frames it made are removed, frozen clips play.
        removeFreezes()
        // Smart reframe first kept its points on clips, relative to the take.
        adoptClipReframes()
    }

    public var locale: Locale { Locale(identifier: localeIdentifier) }

    public func audioClip(id: AudioClip.ID) -> AudioClip? {
        audio.first { $0.id == id }
    }

    public func segment(id: Segment.ID) -> Segment? {
        segments.first { $0.id == id }
    }

    public func recording(id: Recording.ID) -> Recording? {
        recordings.first { $0.id == id }
    }
}

public enum ProjectError: Error, Hashable, Sendable {
    case segmentNotFound(Segment.ID)
    case takeNotFound(Take.ID)
}

extension Project {
    /// Adds a take to one segment. This is the whole retake operation:
    /// no other segment changes, because timeline positions are derived, never stored.
    ///
    /// Selecting the new take clears that segment's captions; they belong to the old take's
    /// speech and are regenerated from the new transcript.
    public mutating func addTake(_ take: Take, toSegment segmentID: Segment.ID, select: Bool = true) throws {
        guard let index = segments.firstIndex(where: { $0.id == segmentID }) else {
            throw ProjectError.segmentNotFound(segmentID)
        }
        segments[index].takes.append(take)
        if select {
            segments[index].selectedTakeID = take.id
            segments[index].captions.removeAll()
        }
        updatedAt = .now
    }

    public mutating func selectTake(_ takeID: Take.ID, inSegment segmentID: Segment.ID) throws {
        guard let index = segments.firstIndex(where: { $0.id == segmentID }) else {
            throw ProjectError.segmentNotFound(segmentID)
        }
        guard segments[index].takes.contains(where: { $0.id == takeID }) else {
            throw ProjectError.takeNotFound(takeID)
        }
        guard segments[index].selectedTakeID != takeID else { return }
        segments[index].selectedTakeID = takeID
        // The old take's captions describe somebody else's sentence. The new take's are read from
        // its own words — or there are none yet, until it has been listened to.
        segments[index].refreshCaptions(maxWordsPerCue: captionStyle.maxWordsPerCue)
        updatedAt = .now
    }
}


extension Project {
    /// Where the voice is, in finished-video time.
    ///
    /// Ducking needs to know when someone is speaking, and this is the honest answer the document
    /// can give without listening to anything: a segment with a take is a person talking. Derived
    /// on demand rather than stored, like every other timeline fact here.
    public var spokenRanges: [MediaTimeRange] {
        var ranges: [MediaTimeRange] = []
        var cursor = 0.0
        for segment in segments {
            let length = segment.barWeight
            if segment.selectedTake != nil {
                ranges.append(
                    MediaTimeRange(start: MediaTime(seconds: cursor), duration: MediaTime(seconds: length))
                )
            }
            cursor += length
        }
        return ranges
    }

    public mutating func updateAudio(id: AudioClip.ID, _ change: (inout AudioClip) -> Void) {
        guard let index = audio.firstIndex(where: { $0.id == id }) else { return }
        change(&audio[index])
        updatedAt = .now
    }

    public mutating func removeAudio(id: AudioClip.ID) {
        audio.removeAll { $0.id == id }
        updatedAt = .now
    }
}

extension Project {
    /// Takes out every freeze: clips that were only a held frame, and the hold on any other clip.
    mutating func removeFreezes() {
        if segments.count > 1 {
            let kept = segments.filter { $0.metadata["freezeFrame"] != "1" }
            if !kept.isEmpty { segments = kept }
        }
        for index in segments.indices where segments[index].playback.freeze != nil {
            segments[index].playback.freeze = nil
            segments[index].metadata["freezeFrame"] = nil
        }
    }
}

extension Project {
    /// Moves reframe points kept on clips (builds 55–56) to their recordings, in file seconds.
    mutating func adoptClipReframes() {
        for index in segments.indices where !segments[index].smartReframe.isEmpty {
            let points = segments[index].smartReframe
            segments[index].smartReframe = []
            guard let take = segments[index].selectedTake,
                  let recording = recordings.firstIndex(where: { $0.id == take.recordingID })
            else { continue }
            let start = take.sourceRange.start.seconds
            let moved = points.map {
                VideoFocusKeyframe(
                    time: start + $0.time,
                    x: $0.x,
                    y: $0.y,
                    zoom: $0.zoom,
                    confidence: $0.confidence,
                    trackingState: $0.trackingState
                )
            }
            let kept = (recordings[recording].reframe ?? []).filter {
                $0.time < start || $0.time > start + take.sourceRange.duration.seconds
            }
            recordings[recording].reframe = (kept + moved).sorted { $0.time < $1.time }
        }
    }
}
