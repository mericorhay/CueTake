import Domain
import Foundation
import Persistence

/// The creator's voice profile: kept on the phone, measured from their own videos.
extension AppModel {
    static let voiceProfileKey = "creator.voiceProfile"

    static func loadVoiceProfile() -> CreatorVoiceProfile {
        UserDefaults.standard.data(forKey: voiceProfileKey)
            .flatMap { try? JSONDecoder().decode(CreatorVoiceProfile.self, from: $0) } ?? CreatorVoiceProfile()
    }

    static func saveVoiceProfile(_ profile: CreatorVoiceProfile) {
        UserDefaults.standard.set(try? JSONEncoder().encode(profile), forKey: voiceProfileKey)
    }

    /// Listens again to what the creator said in their latest videos — the open project first,
    /// then up to twenty from the library, newest first — and takes the measurement, keeping what
    /// they wrote themselves.
    func measureVoiceProfile() async {
        guard !isMeasuringVoice else { return }
        isMeasuringVoice = true
        defer { isMeasuringVoice = false }
        var transcripts = Self.transcripts(of: project)
        let others = library
            .filter { $0.id != project.id }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(20)
        for summary in others {
            guard let other = try? await dependencies.projectStore.load(summary.id) else { continue }
            transcripts += Self.transcripts(of: other)
        }
        let measured = VoiceMeasure.profile(from: transcripts, localeIdentifier: project.localeIdentifier)
        voiceProfile.adopt(measured)
    }
}
