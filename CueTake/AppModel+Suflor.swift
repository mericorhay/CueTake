import AIServices
import AVFoundation
import Domain
import Foundation
import Persistence
import SettingsFeature
import SpeechEngine
import SuflorFeature
import UIKit

/// The suflör's lines to the rest of the app: the server that writes its cards and the
/// transcriber that finds the brand's words in a saved stream.
extension AppModel {
    func startSuflor() {
        let suflor = suflorModel
        suflor.localeIdentifier = project.localeIdentifier
        let client = dependencies.assistantClient
        if client.isConfigured {
            suflor.writer = { [weak self] brief, locale, voice in
                guard let self, self.settingsModel.settings.aiProcessing == .allowCloud else {
                    throw SuflorModel.WriteError.cloudOff
                }
                do {
                    return try await client.writeSuflor(brief, localeIdentifier: locale, voice: voice)
                } catch AssistantClient.AssistantError.offline {
                    throw SuflorModel.WriteError.offline
                } catch AssistantClient.AssistantError.rejected(let status) {
                    throw SuflorModel.WriteError.server(status)
                } catch {
                    throw SuflorModel.WriteError.empty
                }
            }
            suflor.allowCloud = { [weak self] in
                self?.settingsModel.update(\.aiProcessing, to: .allowCloud)
            }
        } else {
            suflor.writer = nil
        }
        suflor.voiceLoader = { [weak self] in await self?.suflorVoiceSample() }
        let speech = dependencies.speech
        let locale = project.localeIdentifier
        suflor.verifier = { url, items in
            try await Self.findSaid(items, in: url, speech: speech, localeIdentifier: locale)
        }
        go(to: .suflor)
    }

    /// The creator's speech from their latest videos: the open project first, then the library,
    /// newest first, until there is enough to hear how they talk.
    func suflorVoiceSample() async -> String? {
        var transcripts = Self.transcripts(of: project)
        let others = library
            .filter { $0.id != project.id }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(8)
        for summary in others {
            if SuflorVoice.wordCount(SuflorVoice.sample(from: transcripts)) >= 450 { break }
            guard let other = try? await dependencies.projectStore.load(summary.id) else { continue }
            transcripts += Self.transcripts(of: other)
        }
        return SuflorVoice.sample(from: transcripts)
    }

    private static func transcripts(of project: Project) -> [Transcript] {
        project.segments.flatMap(\.takes).compactMap(\.transcript).filter { !$0.words.isEmpty }
    }

    /// Listens to a recording on this phone and returns where each item was first said, with a
    /// frame from that moment.
    nonisolated static func findSaid(_ items: [String], in url: URL, speech: any SpeechTranscribing, localeIdentifier: String) async throws -> [SuflorProof] {
        let transcript = try await speech.transcribeFile(at: url, localeIdentifier: localeIdentifier, hints: items)
        var proofs = SuflorProof.find(items, in: transcript.words, localeIdentifier: localeIdentifier)
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        for index in proofs.indices {
            let time = CMTime(seconds: proofs[index].seconds + 0.3, preferredTimescale: 600)
            if let shot = try? await generator.image(at: time) {
                proofs[index].frame = UIImage(cgImage: shot.image).jpegData(compressionQuality: 0.72)
            }
        }
        return withExtendedLifetime(asset) { proofs }
    }
}
