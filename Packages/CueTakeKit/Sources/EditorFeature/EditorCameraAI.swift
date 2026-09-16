import Domain
import Foundation
import MediaEngine

/// Face tracks found before an AI step writes them. Analysis is slow and asynchronous; the step
/// itself is not, so the finding happens first and the writing happens with the step.
final class AIFaceTrackBox {
    struct Found {
        var recordingID: Recording.ID
        var range: ClosedRange<Double>
        var points: [VideoFocusKeyframe]
    }
    var found: [Found] = []
}

// MARK: - The AI's camera

extension EditorModel {
    /// The clip, take and source second under a moment of the finished video.
    func sourcePlace(at time: Double) -> (index: Int, take: Take, recordingIndex: Int, source: Double)? {
        var start = 0.0
        for (index, segment) in project.segments.enumerated() {
            let end = start + segment.barWeight
            if time >= start - 0.0001, time < end || index == project.segments.count - 1 {
                guard let take = segment.selectedTake,
                      segment.playback.freeze == nil,
                      let recordingIndex = project.recordings.firstIndex(where: { $0.id == take.recordingID })
                else { return nil }
                let local = min(max(time - start, 0), segment.barWeight)
                let source = take.sourceRange.start.seconds
                    + segment.playback.sourceOffset(forTimeline: local, sourceLength: take.sourceRange.duration.seconds)
                return (index, take, recordingIndex, source)
            }
            start = end
        }
        return nil
    }

    /// Lays or changes a camera move the way the AI asked. A new move stays inside the clip it
    /// starts in, and replaces whatever moves it covers there.
    func aiCameraMove(_ request: CameraMoveRequest) -> [AITarget]? {
        if let move = request.move {
            guard let id = UUID(uuidString: move),
                  let recording = project.recordings.first(where: { $0.cameraMotions?.contains { $0.id == id } == true })
            else { return nil }
            updateCameraMotion(id) {
                if let kind = request.kind { $0.kind = kind }
                if let amount = request.amount { $0.amount = amount }
                if let feel = request.feel { $0.feel = feel }
            }
            if let at = request.at, let first = sourcePlace(at: at),
               project.recordings[first.recordingIndex].id == recording.id {
                let current = timelineRange(ofCameraMotion: id)
                let length = current.map { $0.upperBound - $0.lowerBound } ?? 2
                let end = min(request.to ?? at + length, timelineRange(ofSegmentAt: first.index).upperBound)
                if let last = sourcePlace(at: max(at + 0.1, end) - 0.001),
                   last.recordingIndex == first.recordingIndex {
                    setCameraMotionRange(
                        recordingID: recording.id,
                        motionID: id,
                        sourceStart: min(first.source, last.source),
                        sourceEnd: max(first.source, last.source)
                    )
                }
            }
            return [.recording(recording.id)]
        }

        guard let at = request.at, let place = sourcePlace(at: at) else { return nil }
        let kind = request.kind ?? .pushIn
        let clip = timelineRange(ofSegmentAt: place.index)
        let fallback: Double = switch kind {
        case .punch: 1
        case .hold: clip.upperBound - at
        case .pushIn, .pullOut: 2
        }
        let end = min(max(request.to ?? at + fallback, at + 0.2), clip.upperBound)
        guard end - at >= 0.2 else { return nil }
        let segment = project.segments[place.index]
        let take = place.take
        let other = take.sourceRange.start.seconds + segment.playback.sourceOffset(
            forTimeline: end - clip.lowerBound,
            sourceLength: take.sourceRange.duration.seconds
        )
        let lower = min(place.source, other), upper = max(place.source, other)
        guard upper - lower >= 0.1 else { return nil }

        let recordingIndex = place.recordingIndex
        let kept = (project.recordings[recordingIndex].cameraMotions ?? []).filter {
            $0.end <= lower + 0.0001 || $0.start >= upper - 0.0001
        }
        let recipe = CameraMotionRecipe(
            sourceRange: MediaTimeRange(start: MediaTime(seconds: lower), duration: MediaTime(seconds: upper - lower)),
            amount: request.amount ?? (kind == .punch ? 0.2 : 0.12),
            // Stored in source time: a move on a reversed clip is its mirror in the file.
            kind: kind.facingTimeline(isReversed: segment.playback.isReversed),
            feel: request.feel ?? (kind == .punch ? .energetic : .natural)
        )
        project.recordings[recordingIndex].cameraMotions = (kept + [recipe]).sorted { $0.start < $1.start }
        project.mainVideoPlacement.fillsFrame = true
        project.mainVideoPlacement.zoom = nil
        return [.recording(project.recordings[recordingIndex].id)]
    }

    /// The clips a clip reference names: that one, or every clip with footage.
    func aiTrackClips(_ clip: String?) -> [Segment] {
        project.segments.enumerated().compactMap { index, segment in
            if let clip, self.index(ofClip: clip) != index { return nil }
            guard segment.selectedTake != nil, segment.playback.freeze == nil else { return nil }
            return segment
        }
    }

    /// Finds the speaker's face through each clip, on the device.
    func aiFindFaces(in segments: [Segment], closeness: Double) async -> [AIFaceTrackBox.Found] {
        guard let mediaDirectory else { return [] }
        let zoom = 1 + min(max(closeness, 0.05), 0.3)
        var found: [AIFaceTrackBox.Found] = []
        for segment in segments {
            guard !Task.isCancelled,
                  let take = segment.selectedTake,
                  let recording = project.recording(id: take.recordingID)
            else { continue }
            let url = mediaDirectory.appending(
                path: (recording.relativePath as NSString).lastPathComponent,
                directoryHint: .notDirectory
            )
            let start = take.sourceRange.start.seconds
            let length = take.sourceRange.duration.seconds
            guard let focuses = try? await SubjectTracker().faceFocus(in: url, sourceStart: start, duration: length),
                  focuses.count >= 2
            else { continue }
            found.append(AIFaceTrackBox.Found(
                recordingID: recording.id,
                range: start...(start + length),
                points: focuses.map {
                    VideoFocusKeyframe(
                        time: start + $0.time,
                        x: $0.x,
                        y: $0.y,
                        // Filling a frame of the same shape leaves nothing to move within;
                        // a little closer is what lets the camera follow.
                        zoom: zoom,
                        confidence: $0.confidence,
                        trackingState: .tracking
                    )
                }
            ))
        }
        return found
    }

    /// Writes found face tracks, replacing what those clips followed before.
    func aiApplyFaceTracks(_ found: [AIFaceTrackBox.Found]) -> [AITarget]? {
        var targets: [AITarget] = []
        for track in found {
            guard let index = project.recordings.firstIndex(where: { $0.id == track.recordingID }) else { continue }
            let kept = (project.recordings[index].reframe ?? []).filter {
                $0.time < track.range.lowerBound - 0.0001 || $0.time > track.range.upperBound + 0.0001
            }
            project.recordings[index].reframe = (kept + track.points).sorted { $0.time < $1.time }
            targets.append(.recording(track.recordingID))
        }
        guard !targets.isEmpty else { return nil }
        project.mainVideoPlacement.fillsFrame = true
        return targets
    }

    func aiRemoveTracks(_ clip: String?) -> [AITarget]? {
        var targets: [AITarget] = []
        for segment in aiTrackClips(clip) {
            guard let recordingID = segment.selectedTake?.recordingID else { continue }
            let before = project.recording(id: recordingID)?.reframe
            removeSubjectTrack(forSegment: segment.id)
            if project.recording(id: recordingID)?.reframe != before { targets.append(.recording(recordingID)) }
        }
        return targets.isEmpty ? nil : targets
    }
}
