import Analytics
import AIServices
import DesignSystem
import Domain
import EditorFeature
import Foundation
import MediaEngine
import Persistence
import SettingsFeature

/// Stock B-roll: the server picks the moments and searches a library free for commercial use; the
/// app downloads the shots and brings them into the project like any imported clip.
extension AppModel {
    func connectStockBroll() {
        guard dependencies.assistantClient.isConfigured else {
            editorModel.stockBrollFinder = nil
            return
        }
        let client = dependencies.assistantClient
        let store = dependencies.projectStore
        editorModel.stockBrollFinder = { [weak self] count in
            guard let self else { return [] }
            guard self.settingsModel.settings.aiProcessing == .allowCloud else {
                throw DescribedError(message: Self.assistantFailureMessage(AssistantClient.AssistantError.declined))
            }
            let project = self.editorModel.project
            let sentences = project.spokenSentences
            guard !sentences.isEmpty else { throw DescribedError(message: AppLocalization.string("broll.needsSpeech")) }
            let size = project.format.renderSize

            let shots: [StockShot]
            do {
                shots = try await client.stockBroll(for: sentences, count: count, portrait: size.height >= size.width)
            } catch let error as AssistantClient.AssistantError where error == .rejected(status: 503) {
                throw DescribedError(message: AppLocalization.string("broll.notConfigured"))
            } catch {
                throw DescribedError(message: Self.assistantFailureMessage(error))
            }

            Analytics.track("stock_broll", ["shots": .int(shots.count), "asked": .int(count)])
            guard let media = try? await store.mediaDirectory(for: project.id) else { return [] }
            var found: [StockBroll] = []
            for shot in shots {
                guard let imported = await Self.fetchStockShot(shot, into: media) else { continue }
                let clip = GeneratedClip(recording: imported.recording, take: imported.take, thumbnail: nil)
                found.append(StockBroll(clip: clip, title: shot.query, at: shot.at, seconds: shot.seconds))
            }
            return found
        }
    }

    /// Gives the editor its beat finder: the music file, read on the phone.
    func connectBeats() {
        let store = dependencies.projectStore
        editorModel.beatFinder = { [weak self] clip in
            guard let self, let media = try? await store.mediaDirectory(for: self.editorModel.project.id) else { return nil }
            let file = media.appending(path: (clip.relativePath as NSString).lastPathComponent, directoryHint: .notDirectory)
            return await BeatDetector.grid(for: file)
        }
    }

    /// Downloads one shot and imports it beside the footage.
    nonisolated static func fetchStockShot(_ shot: StockShot, into media: URL) async -> MediaImporter.ImportedClip? {
        guard let (downloaded, response) = try? await AssistantTransport.download(from: shot.video.url),
              ((response as? HTTPURLResponse)?.statusCode ?? 200) < 300
        else { return nil }
        let file = FileManager.default.temporaryDirectory.appending(path: "stock-\(shot.video.id).mp4", directoryHint: .notDirectory)
        try? FileManager.default.removeItem(at: file)
        guard (try? FileManager.default.moveItem(at: downloaded, to: file)) != nil,
              let clip = try? await MediaImporter().importClip(from: file, into: media)
        else { return nil }
        return clip
    }
}
