import Domain
import Foundation

/// Drawing on a sound's volume curve, from where the playhead is.
///
/// "Here" is the playhead because that is where the ear is: the person hears the moment the music
/// is too loud, stops, and pulls it down. A curve drawn with a finger on a strip 30 points tall is
/// a curve drawn wrong.
extension EditorModel {
    /// Seconds into the clip that the playhead is at, or nil when it is not over the clip.
    public func playheadOffset(in id: AudioClip.ID) -> Double? {
        guard let clip = project.audio.first(where: { $0.id == id }) else { return nil }
        let offset = playhead - clip.start.seconds
        guard offset >= 0, offset <= clip.timelineDuration.seconds else { return nil }
        return offset
    }

    /// The key under the playhead, which the level control then edits.
    public func volumeKeyAtPlayhead(_ id: AudioClip.ID) -> VolumeKey? {
        guard let offset = playheadOffset(in: id),
              let clip = project.audio.first(where: { $0.id == id })
        else { return nil }
        return clip.volumeKey(near: offset)
    }

    /// What the curve says at the playhead: the key's own level, or the line between two keys.
    public func automationAtPlayhead(_ id: AudioClip.ID) -> Double {
        guard let offset = playheadOffset(in: id),
              let clip = project.audio.first(where: { $0.id == id })
        else { return 1 }
        return clip.automation(at: offset)
    }

    /// Puts a key under the playhead, or changes the one that is there.
    public func setVolumeKeyAtPlayhead(_ id: AudioClip.ID, level: Double) {
        guard let offset = playheadOffset(in: id) else { return }
        // Snapped onto the key already near the playhead, so nudging the level never leaves a
        // second key a few frames beside the first.
        let at = volumeKeyAtPlayhead(id)?.time ?? offset
        updateAudio(id) { $0.setVolumeKey(at: at, level: level) }
    }

    public func removeVolumeKeyAtPlayhead(_ id: AudioClip.ID) {
        guard let offset = playheadOffset(in: id) else { return }
        updateAudio(id) { $0.removeVolumeKey(near: offset) }
    }

    public func clearVolumeKeys(_ id: AudioClip.ID) {
        updateAudio(id) { $0.volumeKeys = nil }
    }
}
