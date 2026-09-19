import Foundation
import Testing
@testable import Domain

struct VoiceProfileTests {
    /// Words said every `step` seconds, with a longer pause after each `sentence` words.
    private func speech(_ text: String, step: Double = 0.4, sentence: Int = 5, pause: Double = 1.0) -> Transcript {
        var at = 0.0
        var words: [TimedWord] = []
        for (index, word) in text.split(separator: " ").enumerated() {
            words.append(TimedWord(text: String(word), range: MediaTimeRange(start: MediaTime(seconds: at), duration: MediaTime(seconds: 0.3))))
            at += (index + 1).isMultiple(of: sentence) ? pause : step
        }
        return Transcript(localeIdentifier: "tr-TR", words: words)
    }

    @Test func measuresPaceSentencesFillersAndOpenings() {
        let text = "selam millet bugün yani kahve deniyoruz bu makine yani çok hızlı şey ısıtıyor kodum kahve on linki bio da"
        let profile = VoiceMeasure.profile(from: [speech(text), speech(text)], localeIdentifier: "tr-TR")
        #expect(profile.measuredVideos == 2)
        #expect(abs((profile.sentenceWords ?? 0) - 4.75) < 0.01)
        #expect(profile.fillers.first == "yani")
        #expect(profile.openings == ["selam millet bugün yani kahve"])
        let pace = profile.wordsPerMinute ?? 0
        #expect(pace > 110 && pace < 130)
    }

    @Test func aNewMeasurementKeepsWhatTheCreatorWrote() {
        var mine = CreatorVoiceProfile(openings: ["Selam kanka"], avoid: ["mükemmel"])
        mine.adopt(CreatorVoiceProfile(wordsPerMinute: 140, openings: ["başka"], callsToAction: ["link bio da"], measuredVideos: 3))
        #expect(mine.openings == ["Selam kanka"])
        #expect(mine.callsToAction == ["link bio da"])
        #expect(mine.avoid == ["mükemmel"])
        #expect(mine.pace == 140)
        mine.usesPace = false
        #expect(mine.pace == nil)
        #expect(mine.promptText?.contains("mükemmel") == true)
    }
}
