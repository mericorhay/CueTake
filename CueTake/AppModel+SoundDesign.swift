import DesignSystem
import Domain
import EditorFeature
import Foundation
import MediaEngine
import Persistence

/// Sound design: the sounds are made on the phone and written beside the footage, so the editor
/// and a workflow lay in the same files and nothing licensed is ever shipped.
extension AppModel {
    /// Gives the editor its sound designer: the planner for where, the synth for what.
    func connectSoundDesign() {
        let store = dependencies.projectStore
        editorModel.soundDesigner = { [weak self] options, document in
            guard let self,
                  let media = try? await store.mediaDirectory(for: self.editorModel.project.id)
            else { return [] }
            return await Self.soundDesignClips(options, document: document, media: media)
        }
    }

    /// The sounds for a document, their files made off the main thread.
    nonisolated static func soundDesignClips(_ options: SoundDesignOptions, document: EditDocument, media: URL) async -> [AudioClip] {
        let cues = SoundDesign.plan(options, for: document)
        guard !cues.isEmpty else { return [] }
        let kinds = Set(cues.map(\.kind))
        let files = await Task.detached(priority: .userInitiated) {
            var made: [SoundCueKind: URL] = [:]
            for kind in kinds {
                if let url = try? SoundDesignSynth.file(kind, in: media) { made[kind] = url }
            }
            return made
        }.value

        return cues.compactMap { cue in
            guard let file = files[cue.kind] else { return nil }
            var clip = AudioClip(
                name: AppLocalization.string(String.LocalizationValue(stringLiteral: "sfx.name." + cue.kind.rawValue)),
                relativePath: "media/\(file.lastPathComponent)",
                role: .effect,
                start: MediaTime(seconds: cue.start),
                sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: cue.kind.seconds)),
                fadeIn: .zero,
                fadeOut: .zero,
                ducksUnderVoice: false
            )
            clip.setDecibels(cue.decibels)
            return clip
        }
    }
}
