import Domain
import Foundation

/// The timing edits the timeline's bars make directly, for sounds and captions. (Texts, pictures,
/// effects and added videos have theirs beside their own models.)
extension EditorModel {
    // MARK: Sound

    public func moveAudio(_ id: AudioClip.ID, to seconds: Double) {
        updateAudio(id) { $0.start = MediaTime(seconds: max(0, seconds)) }
    }

    /// Moves where a sound starts, keeping where it ends: the front of the file is trimmed or
    /// brought back, as far as the file begins.
    public func setAudioStartEdge(_ id: AudioClip.ID, to seconds: Double) {
        guard let clip = project.audio.first(where: { $0.id == id }) else { return }
        let end = clip.timelineRange.end.seconds
        let speed = max(0.1, clip.speed)
        let wanted = min(max(0, seconds), end - 0.2)
        // Timeline seconds to file seconds, and never before the file's first sample.
        let shift = max((wanted - clip.start.seconds) * speed, -clip.sourceRange.start.seconds)
        let newSourceStart = clip.sourceRange.start.seconds + shift
        let newLength = clip.sourceRange.duration.seconds - shift
        guard newLength >= 0.2 * speed else { return }
        updateAudio(id) {
            $0.start = MediaTime(seconds: clip.start.seconds + shift / speed)
            $0.sourceRange = MediaTimeRange(start: MediaTime(seconds: newSourceStart), duration: MediaTime(seconds: newLength))
            // The drawn volume stays on the music it was drawn on, not at a distance from an edge.
            $0.shiftVolumeKeys(by: -shift / speed)
        }
    }

    /// Moves where a sound ends, keeping where it starts.
    public func setAudioEnd(_ id: AudioClip.ID, to seconds: Double) {
        guard let clip = project.audio.first(where: { $0.id == id }) else { return }
        let speed = max(0.1, clip.speed)
        let length = max(0.2, seconds - clip.start.seconds) * speed
        updateAudio(id) {
            $0.sourceRange = MediaTimeRange(start: $0.sourceRange.start, duration: MediaTime(seconds: length))
        }
    }

    // MARK: Captions

    /// Sets when a caption is on screen, in finished-video seconds, inside the clip it belongs to.
    ///
    /// Captions are stored in their clip's own footage seconds, so the times are taken back
    /// through the clip's speed. A caption cannot leave its clip; a frozen clip's captions keep
    /// their times, since a held frame has no footage clock to put them on.
    public func retimeCaption(_ id: CaptionCue.ID, start: Double, end: Double) {
        guard let index = segmentIndex(ofCaption: id) else { return }
        let segment = project.segments[index]
        guard segment.playback.freeze == nil else { return }
        let clipStart = self.start(at: index)
        let stretch = segment.sourceSeconds > 0.01 ? segment.barWeight / segment.sourceSeconds : 1
        let length = segment.sourceSeconds
        let from = min(max(0, (start - clipStart) / stretch), max(0, length - 0.15))
        let to = min(max(from + 0.15, (end - clipStart) / stretch), length)
        updateCaption(id, at: index) {
            $0.range = MediaTimeRange(start: MediaTime(seconds: from), duration: MediaTime(seconds: to - from))
        }
    }
}
