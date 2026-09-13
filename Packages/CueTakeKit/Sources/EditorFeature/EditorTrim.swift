import Domain
import Foundation

/// Trimming a clip from either end, in source seconds.
///
/// The end was always trimmable by dragging the clip's edge. The start was not — which is the end
/// that matters most, because it is where every take begins with someone reaching back from the
/// shutter. Both are here, with words and captions following the footage.
extension EditorModel {
    /// The recording behind a segment's chosen take, for knowing how far a trim may go.
    func recordingLength(at index: Int) -> Double? {
        guard project.segments.indices.contains(index),
              let take = project.segments[index].selectedTake,
              let recording = project.recordings.first(where: { $0.id == take.recordingID })
        else { return nil }
        return recording.duration.seconds
    }

    /// Moves a clip's start by `delta` seconds of footage: positive trims it off, negative brings
    /// footage back from before it.
    public func trimStart(by delta: Double, at index: Int) {
        guard project.segments.indices.contains(index),
              let takeID = project.segments[index].selectedTakeID,
              let takeIndex = project.segments[index].takes.firstIndex(where: { $0.id == takeID }),
              project.segments[index].playback.freeze == nil
        else { return }

        let take = project.segments[index].takes[takeIndex]
        let start = take.sourceRange.start.seconds
        let end = take.sourceRange.end.seconds
        let newStart = min(max(0, start + delta), end - 0.3)
        let shift = newStart - start
        guard abs(shift) > 0.001 else { return }

        record("editor.change.trim", symbol: "arrow.left.and.right", coalescing: "trim-start-\(index)")

        let previousCaptions = project.segments[index].captions
        var updated = take
        updated.sourceRange = MediaTimeRange(start: MediaTime(seconds: newStart), duration: MediaTime(seconds: end - newStart))
        if let transcript = take.transcript {
            // Words keep their moment in the recording; relative to the new start they move by the
            // shift. Anything now before the start is gone with the footage.
            updated.transcript = transcript.slice(from: shift, to: end - start)
        }
        project.segments[index].takes[takeIndex] = updated
        project.segments[index].refreshCaptions(
            maxWordsPerCue: project.captionStyle.maxWordsPerCue,
            carrying: previousCaptions.map { $0.shifted(by: -shift) }
        )
        project.updatedAt = .now
        seek(to: min(playhead, duration))
    }

    /// Moves a clip's end by `delta` seconds of footage.
    public func trimEnd(by delta: Double, at index: Int) {
        guard project.segments.indices.contains(index) else { return }
        let segment = project.segments[index]
        // `setDuration` takes the length on the timeline; speed turns source seconds into those.
        setDuration(segment.playback.timelineSeconds(forSource: segment.sourceSeconds + delta), forSegmentAt: index)
    }
}
