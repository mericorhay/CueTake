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
    public var createdAt: Date
    public var updatedAt: Date
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        title: String,
        format: VideoFormat = .vertical1080,
        localeIdentifier: String,
        segments: [Segment] = [],
        recordings: [Recording] = [],
        captionStyle: CaptionStyle = .standard,
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
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.metadata = metadata
    }

    public var locale: Locale { Locale(identifier: localeIdentifier) }

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
        segments[index].captions.removeAll()
        updatedAt = .now
    }
}
