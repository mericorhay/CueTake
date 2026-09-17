import Foundation
import Testing
@testable import Domain

struct PrompterPaceTests {
    @Test func paceIsMeasuredOverTheWindowAndResetsOnAJumpBack() {
        var meter = PaceMeter(window: 12)
        #expect(meter.wordsPerMinute == nil)
        // Two and a half words a second: 150 a minute.
        for step in 0...10 {
            meter.record(word: step * 5, at: Double(step) * 2)
        }
        let pace = meter.wordsPerMinute ?? 0
        #expect(abs(pace - 150) < 0.5)
        #expect(PaceMeter.verdict(pace, target: 150) == .good)
        #expect(PaceMeter.verdict(200, target: 150) == .fast)
        #expect(PaceMeter.verdict(90, target: 150) == .slow)

        meter.record(word: 3, at: 22)
        #expect(meter.wordsPerMinute == nil)
    }

    @Test func tooLittleReadingSaysNothing() {
        var meter = PaceMeter()
        meter.record(word: 0, at: 0)
        meter.record(word: 10, at: 1)
        #expect(meter.wordsPerMinute == nil)
    }

    @Test func timeLeftCountsTheRestOfTheScript() {
        let scripts = ["one two three four", "five six", "seven eight nine ten"]
        #expect(ScriptTiming.wordCount(scripts) == 10)
        #expect(abs(ScriptTiming.remainingSeconds(scripts: scripts, segment: 0, word: -1, wordsPerMinute: 60) - 10) < 0.001)
        // On "two": two words left here, then six more.
        #expect(abs(ScriptTiming.remainingSeconds(scripts: scripts, segment: 0, word: 1, wordsPerMinute: 60) - 8) < 0.001)
        #expect(ScriptTiming.globalWord(scripts: scripts, segment: 2, word: 1) == 7)
        #expect(ScriptTiming.label(83) == "1:23")
    }

    @Test func starsMarkStressAndPunctuationEndsSentences() {
        let stressed = ScriptText.emphasis("*never*,")
        let plain = ScriptText.emphasis("plain")
        let star = ScriptText.emphasis("*")
        #expect(stressed.text == "never,")
        #expect(stressed.isEmphasized)
        #expect(plain.text == "plain")
        #expect(!plain.isEmphasized)
        #expect(star.text == "*")
        #expect(!star.isEmphasized)

        let words = ["Hello", "there.", "This", "is", "it!", "\"Really?\"", "Yes"]
        #expect(ScriptText.sentence(around: 3, in: words) == 2...4)
        #expect(ScriptText.sentence(around: 0, in: words) == 0...1)
        #expect(ScriptText.sentence(around: 5, in: words) == 5...5)
        #expect(ScriptText.sentence(around: 6, in: words) == 6...6)
        #expect(ScriptText.sentence(around: 9, in: words) == nil)
    }

    @Test func aRetakeIsTrimmedToItsSpeech() throws {
        let words = [
            TimedWord(text: "Hello", range: MediaTimeRange(start: MediaTime(seconds: 2), duration: MediaTime(seconds: 0.4))),
            TimedWord(text: "there.", range: MediaTimeRange(start: MediaTime(seconds: 2.5), duration: MediaTime(seconds: 0.5))),
        ]
        let take = Take(
            recordingID: UUID(),
            sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 6)),
            status: .ready,
            transcript: Transcript(localeIdentifier: "en", words: words)
        )
        let trimmed = try #require(take.trimmedToSpeech())
        #expect(abs(trimmed.sourceRange.start.seconds - 1.75) < 0.001)
        #expect(abs(trimmed.sourceRange.duration.seconds - 1.65) < 0.001)
        #expect(abs((trimmed.transcript?.words.first?.range.start.seconds ?? 0) - 0.25) < 0.001)
        #expect(trimmed.id == take.id)

        // Nothing to trim, or nothing heard: left alone.
        #expect(trimmed.trimmedToSpeech() == nil)
        var silent = take
        silent.transcript = nil
        #expect(silent.trimmedToSpeech() == nil)
    }
}
