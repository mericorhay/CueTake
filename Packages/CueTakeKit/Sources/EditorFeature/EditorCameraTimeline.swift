import Domain
import Foundation
import SwiftUI

/// A face or subject track as the timeline shows it: one bar per clip that follows something.
public struct SubjectTrackSpan: Identifiable, Hashable, Sendable {
    public var id: Segment.ID { segmentID }
    public var segmentID: Segment.ID
    public var recordingID: Recording.ID
    /// On the finished video.
    public var start: Double
    public var end: Double
    public var segmentStart: Double
    public var segmentEnd: Double
    /// Moments where the subject was lost, on the finished video.
    public var issueTimes: [Double]
}

// MARK: - Camera moves and tracks on the timeline
//
// Every camera decision is a bar on the timeline: selected there, stretched there, removed there.
// The Zoom and Track tools only create them; everything after that happens against the timeline.

extension EditorModel {
    // MARK: Selection

    public func select(cameraMotion id: CameraMotionRecipe.ID?) {
        selectedCameraMotion = id
        if id != nil {
            selectedSubjectTrack = nil
            clearOtherSelections()
        }
    }

    public func select(subjectTrack id: Segment.ID?) {
        selectedSubjectTrack = id
        if id != nil {
            selectedCameraMotion = nil
            clearOtherSelections()
        }
    }

    func clearOtherSelections() {
        selectedTransition = nil
        inspectedSegment = nil
        selectedAudio = nil
        selectedOverlay = nil
        selectedEffect = nil
        selectedVideoLayer = nil
    }

    /// The selected move, with the recording it belongs to. Nil once it is gone.
    public var selectedCameraMotionValue: (recipe: CameraMotionRecipe, recordingID: Recording.ID)? {
        guard let id = selectedCameraMotion else { return nil }
        for recording in project.recordings {
            if let recipe = recording.cameraMotions?.first(where: { $0.id == id }) {
                return (recipe, recording.id)
            }
        }
        return nil
    }

    public var selectedSubjectTrackValue: SubjectTrackSpan? {
        guard let id = selectedSubjectTrack else { return nil }
        return subjectTrackSpans.first { $0.segmentID == id }
    }

    // MARK: Camera moves by identity

    public func updateCameraMotion(
        _ id: CameraMotionRecipe.ID,
        coalescing key: String? = nil,
        _ change: (inout CameraMotionRecipe) -> Void
    ) {
        guard let (recordingIndex, motionIndex) = cameraMotionIndex(id),
              var recipe = project.recordings[recordingIndex].cameraMotions?[motionIndex]
        else { return }
        let before = recipe
        change(&recipe)
        recipe.amount = min(max(recipe.amount.isFinite ? recipe.amount : 0.15, 0.02), 1)
        guard recipe != before else { return }
        record("editor.change.zoomRecipe", symbol: "plus.magnifyingglass", coalescing: key.map { "camera-\(id)-\($0)" })
        project.recordings[recordingIndex].cameraMotions?[motionIndex] = recipe
        project.updatedAt = .now
    }

    public func removeCameraMotion(_ id: CameraMotionRecipe.ID) {
        guard let (recordingIndex, _) = cameraMotionIndex(id) else { return }
        record("editor.change.zoomRecipeRemoved", symbol: "minus.magnifyingglass")
        project.recordings[recordingIndex].cameraMotions?.removeAll { $0.id == id }
        if project.recordings[recordingIndex].cameraMotions?.isEmpty == true {
            project.recordings[recordingIndex].cameraMotions = nil
        }
        if selectedCameraMotion == id { selectedCameraMotion = nil }
        project.updatedAt = .now
    }

    /// Where a move sits on the finished video: the first clip that shows it.
    public func timelineRange(ofCameraMotion id: CameraMotionRecipe.ID) -> ClosedRange<Double>? {
        var start = 0.0
        for segment in project.segments {
            defer { start += segment.barWeight }
            guard let take = segment.selectedTake,
                  let recipe = project.recording(id: take.recordingID)?.cameraMotions?.first(where: { $0.id == id })
            else { continue }
            let takeStart = take.sourceRange.start.seconds
            let length = take.sourceRange.duration.seconds
            let lower = max(recipe.start, takeStart), upper = min(recipe.end, takeStart + length)
            guard upper - lower > 0.01,
                  let a = segment.playback.timelineOffset(forSourceOffset: lower - takeStart, sourceLength: length),
                  let b = segment.playback.timelineOffset(forSourceOffset: upper - takeStart, sourceLength: length)
            else { continue }
            return (start + min(a, b))...(start + max(a, b))
        }
        return nil
    }

    private func cameraMotionIndex(_ id: CameraMotionRecipe.ID) -> (Int, Int)? {
        for (r, recording) in project.recordings.enumerated() {
            if let m = recording.cameraMotions?.firstIndex(where: { $0.id == id }) { return (r, m) }
        }
        return nil
    }

    /// The free stretch of source around a moment, inside the take and between the moves already
    /// there. New moves go into it, so adding one never wipes another.
    func freeCameraSpan(
        around reference: Double,
        in take: Take,
        motions: [CameraMotionRecipe]
    ) -> ClosedRange<Double> {
        let takeStart = take.sourceRange.start.seconds
        let takeEnd = take.sourceRange.end.seconds
        let lower = motions.filter { $0.end <= reference + 0.0001 }.map(\.end).max().map { max($0, takeStart) } ?? takeStart
        let upper = motions.filter { $0.start >= reference - 0.0001 }.map(\.start).min().map { min($0, takeEnd) } ?? takeEnd
        return lower...max(lower, upper)
    }

    /// A new move of `length` seconds starting at the playhead in the direction the clip plays,
    /// fitted into the free space there.
    func newCameraRange(
        length: Double,
        reference: Double,
        reversed: Bool,
        free: ClosedRange<Double>
    ) -> MediaTimeRange? {
        let span = free.upperBound - free.lowerBound
        guard span >= 0.2 else { return nil }
        let wanted = min(length, span)
        var start = reversed ? reference - wanted : reference
        start = min(max(start, free.lowerBound), free.upperBound - wanted)
        return MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: wanted))
    }

    // MARK: Tracks

    /// Every clip whose picture follows a subject, as bars.
    public var subjectTrackSpans: [SubjectTrackSpan] {
        var result: [SubjectTrackSpan] = []
        var timelineStart = 0.0
        for (index, segment) in project.segments.enumerated() {
            defer { timelineStart += segment.barWeight }
            guard let take = segment.selectedTake,
                  segment.playback.freeze == nil,
                  let recording = project.recording(id: take.recordingID)
            else { continue }
            let points = trackPoints(in: recording, take: take)
            guard points.count >= 2 else { continue }
            let length = take.sourceRange.duration.seconds
            let times = points.compactMap {
                segment.playback.timelineOffset(forSourceOffset: $0.time - take.sourceRange.start.seconds, sourceLength: length)
            }
            guard let low = times.min(), let high = times.max(), high - low > 0.05 else { continue }
            let issues = SubjectTrackReviewPoint.reviewIssues(in: reviewPoints(forSegmentAt: index))
            result.append(SubjectTrackSpan(
                segmentID: segment.id,
                recordingID: recording.id,
                start: timelineStart + low,
                end: timelineStart + high,
                segmentStart: timelineStart,
                segmentEnd: timelineStart + segment.barWeight,
                issueTimes: issues.map(\.timelineTime)
            ))
        }
        return result
    }

    func trackPoints(in recording: Recording, take: Take) -> [VideoFocusKeyframe] {
        let start = take.sourceRange.start.seconds, end = take.sourceRange.end.seconds
        return (recording.reframe ?? [])
            .filter { $0.time >= start - 0.0001 && $0.time <= end + 0.0001 }
            .sorted { $0.time < $1.time }
    }

    /// Confidence points for one clip, converted from recording time to the visible timeline.
    func reviewPoints(forSegmentAt index: Int) -> [SubjectTrackReviewPoint] {
        guard project.segments.indices.contains(index),
              let take = project.segments[index].selectedTake,
              let recording = project.recording(id: take.recordingID)
        else { return [] }
        let segment = project.segments[index]
        let takeStart = take.sourceRange.start.seconds
        let takeLength = take.sourceRange.duration.seconds
        let timelineStart = start(at: index)
        return trackPoints(in: recording, take: take).compactMap { frame in
            guard let localTime = segment.playback.timelineOffset(
                forSourceOffset: frame.time - takeStart,
                sourceLength: takeLength
            ) else { return nil }
            return SubjectTrackReviewPoint(
                id: frame.id,
                timelineTime: timelineStart + localTime,
                confidence: min(max(frame.confidence ?? 1, 0), 1),
                progress: min(max(localTime / max(segment.barWeight, 0.001), 0), 1),
                trackingState: frame.trackingState
            )
        }.sorted { $0.progress < $1.progress }
    }

    /// Stops following in one clip. Other clips of the same recording keep their track.
    public func removeSubjectTrack(forSegment id: Segment.ID) {
        guard let segment = project.segments.first(where: { $0.id == id }),
              let take = segment.selectedTake,
              let recordingIndex = project.recordings.firstIndex(where: { $0.id == take.recordingID })
        else { return }
        let start = take.sourceRange.start.seconds, end = take.sourceRange.end.seconds
        let kept = (project.recordings[recordingIndex].reframe ?? []).filter {
            $0.time < start - 0.0001 || $0.time > end + 0.0001
        }
        guard kept.count != project.recordings[recordingIndex].reframe?.count else { return }
        record("editor.change.subjectTrackRemoved", symbol: "scope")
        project.recordings[recordingIndex].reframe = kept.isEmpty ? nil : kept
        if selectedSubjectTrack == id { selectedSubjectTrack = nil }
        mainSubjectTracking = .idle
        project.updatedAt = .now
    }

    /// Shortens a clip's track from either end, on the timeline. The part cut away plays centred
    /// again, eased in and out by the renderer. Within one drag the original points are the
    /// reference, so dragging an edge back out restores what the drag took.
    public func setSubjectTrackRange(
        forSegment id: Segment.ID,
        start timelineStart: Double? = nil,
        end timelineEnd: Double? = nil,
        coalescing key: String
    ) {
        guard let index = project.segments.firstIndex(where: { $0.id == id }),
              let take = project.segments[index].selectedTake,
              let recordingIndex = project.recordings.firstIndex(where: { $0.id == take.recordingID })
        else { return }
        let segment = project.segments[index]
        let takeStart = take.sourceRange.start.seconds
        let takeLength = take.sourceRange.duration.seconds
        let clipStart = start(at: index)

        let dragKey = "\(id)-\(key)"
        if trackEditOrigin?.key != dragKey || !isAdjustingTimeline {
            trackEditOrigin = (dragKey, trackPoints(in: project.recordings[recordingIndex], take: take))
        }
        guard let origin = trackEditOrigin?.points, let first = origin.first, let last = origin.last else { return }

        func source(_ timeline: Double) -> Double {
            let local = min(max(timeline - clipStart, 0), segment.barWeight)
            return takeStart + segment.playback.sourceOffset(forTimeline: local, sourceLength: takeLength)
        }
        // The visible start is the source end when the clip plays backwards.
        var lower = first.time, upper = last.time
        let current = subjectTrackSpans.first { $0.segmentID == id }
        let visibleStart = timelineStart ?? current?.start
        let visibleEnd = timelineEnd ?? current?.end
        if let visibleStart, let visibleEnd {
            let a = source(visibleStart), b = source(visibleEnd)
            if timelineStart != nil { if segment.playback.isReversed { upper = a } else { lower = a } }
            if timelineEnd != nil { if segment.playback.isReversed { lower = b } else { upper = b } }
        }
        lower = min(max(lower, first.time), last.time)
        upper = max(min(upper, last.time), first.time)
        guard upper - lower >= 0.2 else { return }

        var trimmed = origin.filter { $0.time > lower + 0.0001 && $0.time < upper - 0.0001 }
        trimmed.insert(Self.focus(in: origin, at: lower), at: 0)
        trimmed.append(Self.focus(in: origin, at: upper))

        let start = takeStart, end = takeStart + takeLength
        let outside = (project.recordings[recordingIndex].reframe ?? []).filter {
            $0.time < start - 0.0001 || $0.time > end + 0.0001
        }
        let updated = (outside + trimmed).sorted { $0.time < $1.time }
        guard updated != project.recordings[recordingIndex].reframe else { return }
        record("editor.change.subjectTrackRange", symbol: "scope", coalescing: "track-\(dragKey)")
        project.recordings[recordingIndex].reframe = updated
        project.updatedAt = .now
    }

    /// The tracked point at a source moment, between the two points around it.
    static func focus(in points: [VideoFocusKeyframe], at time: Double) -> VideoFocusKeyframe {
        guard var previous = points.first else { return VideoFocusKeyframe(time: time, x: 0.5, y: 0.5) }
        for frame in points.dropFirst() {
            if time <= frame.time {
                let fraction = min(max((time - previous.time) / max(0.001, frame.time - previous.time), 0), 1)
                func mix(_ a: Double?, _ b: Double?) -> Double? {
                    guard a != nil || b != nil else { return nil }
                    return (a ?? 1) + ((b ?? 1) - (a ?? 1)) * fraction
                }
                return VideoFocusKeyframe(
                    time: time,
                    x: previous.x + (frame.x - previous.x) * fraction,
                    y: previous.y + (frame.y - previous.y) * fraction,
                    zoom: mix(previous.zoom, frame.zoom),
                    confidence: mix(previous.confidence, frame.confidence),
                    trackingState: fraction < 0.5 ? previous.trackingState : frame.trackingState
                )
            }
            previous = frame
        }
        return VideoFocusKeyframe(
            time: time, x: previous.x, y: previous.y,
            zoom: previous.zoom, confidence: previous.confidence, trackingState: previous.trackingState
        )
    }
}
