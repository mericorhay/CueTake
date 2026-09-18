import AIServices
import AVFoundation
import Domain
import Foundation
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
            suflor.writer = { [weak self] brief, locale in
                guard let self, self.settingsModel.settings.aiProcessing == .allowCloud else {
                    throw AssistantClient.AssistantError.declined
                }
                return try await client.writeSuflor(brief, localeIdentifier: locale)
            }
        } else {
            suflor.writer = nil
        }
        let speech = dependencies.speech
        let locale = project.localeIdentifier
        suflor.verifier = { url, items in
            try await Self.findSaid(items, in: url, speech: speech, localeIdentifier: locale)
        }
        go(to: .suflor)
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
