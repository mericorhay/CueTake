import Foundation

/// One attempt at a segment: a time range inside a `Recording` file.
///
/// A continuous recording of the whole script produces one `Recording` and one take per segment,
/// all pointing into the same file with different `sourceRange`s.
/// A retake produces a new `Recording` and a single new take for that segment.
public struct Take: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var recordingID: Recording.ID
    /// The part of the recording file that belongs to this segment. Trimming edits this range.
    public var sourceRange: MediaTimeRange
    public var status: TakeStatus
    /// Word timings, relative to `sourceRange.start`.
    public var transcript: Transcript?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        recordingID: Recording.ID,
        sourceRange: MediaTimeRange,
        status: TakeStatus = .processing,
        transcript: Transcript? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.recordingID = recordingID
        self.sourceRange = sourceRange
        self.status = status
        self.transcript = transcript
        self.createdAt = createdAt
    }

    public var duration: MediaTime { sourceRange.duration }
}

public enum TakeStatus: Hashable, Sendable, Codable {
    case recording
    /// Recorded; speech analysis / alignment still running.
    case processing
    case ready
    case failed(reason: String)
}

/// A physical media file produced by one capture session.
public struct Recording: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    /// Path relative to the project directory, e.g. "media/<id>.mov". Never absolute:
    /// the app container path changes between installs and restores.
    public var relativePath: String
    public var format: VideoFormat
    public var camera: CameraPosition
    public var duration: MediaTime
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        relativePath: String,
        format: VideoFormat,
        camera: CameraPosition,
        duration: MediaTime,
        createdAt: Date = .now
    ) {
        self.id = id
        self.relativePath = relativePath
        self.format = format
        self.camera = camera
        self.duration = duration
        self.createdAt = createdAt
    }
}
