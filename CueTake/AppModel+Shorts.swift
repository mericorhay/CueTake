import DesignSystem
import AIServices
import AVFoundation
import Domain
import EditorFeature
import Foundation
import Persistence
import SettingsFeature

extension AppModel {
    /// Gives the editor what it needs to find shorts and to open one.
    func connectEditorShorts() {
        let client = dependencies.assistantClient
        guard client.isConfigured else {
            editorModel.highlightRequester = nil
            return connectShortOpening()
        }
        let requester: HighlightRequester = { [weak self] sentences, instruction, length, count in
            guard let self else { throw CancellationError() }
            guard self.settingsModel.settings.aiProcessing == .allowCloud else {
                throw DescribedError(message: Self.assistantFailureMessage(AssistantClient.AssistantError.declined))
            }
            let locale = self.project.localeIdentifier
            do {
                let picks: [HighlightPick] = try await client.highlights(
                    in: sentences,
                    instruction: instruction,
                    length: length,
                    count: count,
                    localeIdentifier: locale
                )
                return picks
            } catch {
                throw DescribedError(message: Self.assistantFailureMessage(error))
            }
        }
        editorModel.highlightRequester = requester
        connectShortOpening()
    }

    private func connectShortOpening() {
        editorModel.onCreateShort = { [weak self] clip in
            Task { await self?.openShort(clip) }
        }
    }

    /// Writes a short cut from the open project, with its footage, and opens it in the editor.
    /// Footage cut from wide video is followed so the speaker stays in the vertical frame.
    func openShort(_ clip: Project) async {
        let store = dependencies.projectStore
        guard let source = try? await store.mediaDirectory(for: project.id),
              let target = try? await store.mediaDirectory(for: clip.id)
        else { return }
        busy = AppLocalization.string("busy.makingShort")
        defer { busy = nil }

        // Hard links: the same bytes under a second name, so a short costs no space.
        let files = FileManager.default
        var wide = false
        for recording in clip.recordings {
            let name = (recording.relativePath as NSString).lastPathComponent
            let from = source.appending(path: name, directoryHint: .notDirectory)
            let to = target.appending(path: name, directoryHint: .notDirectory)
            if !files.fileExists(atPath: to.path(percentEncoded: false)) {
                do {
                    try files.linkItem(at: from, to: to)
                } catch {
                    try? files.copyItem(at: from, to: to)
                }
            }
            if !wide, let track = try? await AVURLAsset(url: from).loadTracks(withMediaType: .video).first,
               let size = try? await track.load(.naturalSize),
               let transform = try? await track.load(.preferredTransform) {
                let upright = CGRect(origin: .zero, size: size).applying(transform)
                wide = abs(upright.width) > abs(upright.height) * 0.75
            }
        }

        saveNow()
        do {
            try await store.save(clip)
        } catch {
            return
        }
        adopt(clip)
        openEditor()
        await refreshLibrary()
        guard wide || clip.needsVerticalReframe else { return }
        guard let media = try? await store.mediaDirectory(for: clip.id) else { return }
        await editorModel.followFacesInAllClips(mediaDirectory: media)
        adoptEditorEdits()
    }
}
