import Domain
import Foundation

/// The sounds an AI step made before it runs, handed to the step that lays them in.
final class AISoundDesignBox {
    var clips: [AudioClip]?
}

/// Sound design in the editor: one tap lays whooshes, pops and hits on what the video already has.
extension EditorModel {
    public var canDesignSound: Bool { soundDesigner != nil && !project.segments.isEmpty }

    public var hasSoundDesign: Bool { project.audio.contains(where: SoundDesign.isAutomatic) }

    /// Replaces the automatic sounds with a fresh set for the video as it is now. One undo step.
    /// Returns how many sounds were laid in.
    @discardableResult
    public func applySoundDesign(_ options: SoundDesignOptions) async -> Int {
        guard let soundDesigner else { return 0 }
        let clips = await soundDesigner(options, document())
        record("editor.change.soundDesign", symbol: "speaker.wave.2.fill")
        layInSoundDesign(clips)
        return clips.count
    }

    public func removeSoundDesign() {
        guard hasSoundDesign else { return }
        record("editor.change.soundDesign", symbol: "speaker.slash")
        project.audio.removeAll(where: SoundDesign.isAutomatic)
        project.updatedAt = .now
    }

    /// Only the automatic sounds are replaced; anything a person added stays.
    func layInSoundDesign(_ clips: [AudioClip]) {
        project.audio.removeAll(where: SoundDesign.isAutomatic)
        project.audio.append(contentsOf: clips)
        project.updatedAt = .now
    }
}
