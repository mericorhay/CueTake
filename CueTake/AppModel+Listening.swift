import AIServices
import Domain
import Foundation
import MediaEngine
import SettingsFeature
import SpeechEngine

/// Hearing a recording twice.
///
/// Two listeners that know nothing of each other — Apple's on the phone and Whisper on the server —
/// hear the same file at the same time. Their words are checked against the sound itself (a word
/// where the file is silent was invented), laid side by side passage by passage, picked by rule,
/// and where they still disagree the server model reads both and chooses. Both versions stay in
/// the project, so the choice can be seen and changed later.
extension AppModel {
    /// Everything both listeners heard in a file, decided.
    ///
    /// Throws only when neither could hear anything at all, with the phone's reason — it is the
    /// one that explains a language or a permission.
    func listen(to url: URL, localeIdentifier: String, script: String) async throws -> TranscriptVersions {
        let speech = dependencies.speech
        let client = dependencies.assistantClient

        // The script's names and numbers, and the brand's, told to both listeners before they hear.
        let hints = SpeechHints.terms(scripts: [script], brand: scriptLibrary.activeBrand, localeIdentifier: localeIdentifier)
        let prompt = SpeechHints.whisperPrompt(script: script, terms: hints, localeIdentifier: localeIdentifier)
        async let deviceResult = Self.deviceTranscript(of: url, speech: speech, localeIdentifier: localeIdentifier, hints: hints)
        let allowsCloud = settingsModel.settings.aiProcessing == .allowCloud
        async let cloudResult: [TimedWord]? = allowsCloud
            ? Self.cloudWords(of: url, client: client, localeIdentifier: localeIdentifier, prompt: prompt)
            : nil
        async let activity = VoiceActivity.measure(url)

        let device = await deviceResult
        let cloud = await cloudResult
        let sound = await activity

        let deviceWords = (try? device.get().words) ?? []
        if deviceWords.isEmpty, cloud?.isEmpty ?? true, case .failure(let error) = device {
            throw error
        }

        // Invented words dropped, then every edge moved onto the sound, so cuts land in silence.
        let voicedDevice = sound.map { $0.snapped($0.voiced(deviceWords)) } ?? deviceWords
        let voicedCloud = cloud.map { words in sound.map { $0.snapped($0.voiced(words)) } ?? words }
        var versions = TranscriptVersions(
            localeIdentifier: localeIdentifier,
            device: voicedDevice,
            cloud: voicedCloud,
            script: script
        )
        // Voice that neither listener wrote down: the "ııı"s the cleanup should see.
        if let sound {
            let sounds = sound.unheardSounds(between: voicedDevice + (voicedCloud ?? []))
            versions.unheardSounds = sounds.isEmpty ? nil : sounds
        }

        let disputed = versions.disputed
        if !disputed.isEmpty, allowsCloud, client.isConfigured,
           let choices = try? await client.judgeSpeech(disputed, script: script, localeIdentifier: localeIdentifier) {
            for (passage, source) in choices {
                versions.choose(source, forPassage: passage, by: .ai)
            }
        }
        return versions
    }

    nonisolated private static func deviceTranscript(
        of url: URL,
        speech: any SpeechTranscribing,
        localeIdentifier: String,
        hints: [String]
    ) async -> Result<Transcript, any Error> {
        do {
            return .success(try await speech.transcribeFile(at: url, localeIdentifier: localeIdentifier, hints: hints))
        } catch {
            return .failure(error)
        }
    }

    /// The server's words, or nil when it could not be asked or did not answer.
    nonisolated private static func cloudWords(
        of url: URL,
        client: AssistantClient,
        localeIdentifier: String,
        prompt: String
    ) async -> [TimedWord]? {
        guard client.isConfigured else { return nil }
        guard let compact = try? await SpeechAudio.compact(url) else { return nil }
        defer { try? FileManager.default.removeItem(at: compact) }
        // The service takes up to 25 MB, which at this size is well over an hour of talking.
        let size = (try? compact.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0, size < 24_000_000 else { return nil }
        return try? await client.transcribe(audio: compact, localeIdentifier: localeIdentifier, prompt: prompt)
    }
}
