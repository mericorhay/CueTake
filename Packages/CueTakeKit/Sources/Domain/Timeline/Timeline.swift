import Foundation

/// The edited video, laid out in absolute time. Always derived from a `Project`, never persisted.
///
/// This is the only place where absolute times exist. The editor UI draws it,
/// MediaEngine turns it into an AVComposition for playback and export.
public struct Timeline: Hashable, Sendable {
    public struct Clip: Hashable, Sendable {
        public var segmentID: Segment.ID
        public var takeID: Take.ID
        public var recordingID: Recording.ID
        /// Range inside the recording file.
        public var sourceRange: MediaTimeRange
        /// Range in the final video.
        public var timelineRange: MediaTimeRange
    }

    public struct PlacedCaption: Hashable, Sendable {
        public var segmentID: Segment.ID
        public var cue: CaptionCue
        public var timelineRange: MediaTimeRange
    }

    public var clips: [Clip]
    public var captions: [PlacedCaption]
    public var duration: MediaTime
    /// Segments left out because they have no ready take. The editor shows these as gaps to record.
    public var missingSegmentIDs: [Segment.ID]

    public func clip(at time: MediaTime) -> Clip? {
        clips.first { $0.timelineRange.contains(time) }
    }

    public func clip(for segmentID: Segment.ID) -> Clip? {
        clips.first { $0.segmentID == segmentID }
    }
}

public enum TimelineBuilder {
    /// Lays the selected, ready take of each segment end to end, in segment order.
    public static func build(from project: Project) -> Timeline {
        var cursor = MediaTime.zero
        var clips: [Timeline.Clip] = []
        var captions: [Timeline.PlacedCaption] = []
        var missing: [Segment.ID] = []

        for segment in project.segments {
            guard let take = segment.selectedTake, take.status == .ready else {
                missing.append(segment.id)
                continue
            }
            let timelineRange = MediaTimeRange(start: cursor, duration: take.duration)
            clips.append(Timeline.Clip(
                segmentID: segment.id,
                takeID: take.id,
                recordingID: take.recordingID,
                sourceRange: take.sourceRange,
                timelineRange: timelineRange
            ))
            for cue in segment.captions {
                captions.append(Timeline.PlacedCaption(
                    segmentID: segment.id,
                    cue: cue,
                    timelineRange: cue.range.offset(by: cursor)
                ))
            }
            cursor = timelineRange.end
        }

        return Timeline(clips: clips, captions: captions, duration: cursor, missingSegmentIDs: missing)
    }
}
