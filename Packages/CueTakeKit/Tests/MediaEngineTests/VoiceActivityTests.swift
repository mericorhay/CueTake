import Domain
import Foundation
import Testing
@testable import MediaEngine

struct VoiceActivityTests {
    /// 20 ms windows: quiet at -70 dB, speech at -20 dB, a breath at -60 dB.
    private func activity(_ spans: [(from: Double, to: Double, level: Float)], length: Double = 4) -> VoiceActivity {
        let count = Int(length / 0.02)
        var levels = [Float](repeating: -70, count: count)
        for span in spans {
            for index in Int((span.from / 0.02).rounded())..<min(count, Int((span.to / 0.02).rounded())) {
                levels[index] = span.level
            }
        }
        return VoiceActivity(levels: levels, window: 0.02)
    }

    private func word(_ text: String, _ start: Double, _ end: Double) -> TimedWord {
        TimedWord(text: text, range: MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: end - start)))
    }

    @Test func edgesMoveOntoTheSound() {
        // Speech from 1.00 to 1.60; the recogniser said 1.10 to 1.50.
        let sound = activity([(1.0, 1.6, -20)])
        let snapped = sound.snapped([word("hello", 1.1, 1.5)])
        let start = snapped[0].range.start.seconds
        let end = snapped[0].range.end.seconds
        #expect(abs(start - 1.0) < 0.021)
        #expect(abs(end - 1.6) < 0.021)

        // Said 0.90 to 1.70: the silence at both edges is let go of.
        let loose = sound.snapped([word("hello", 0.9, 1.7)])
        #expect(abs(loose[0].range.start.seconds - 1.0) < 0.021)
        #expect(abs(loose[0].range.end.seconds - 1.6) < 0.021)
    }

    @Test func wordsNeverCrossTheirNeighbours() {
        let sound = activity([(1.0, 2.0, -20)])
        let snapped = sound.snapped([word("one", 1.1, 1.4), word("two", 1.45, 1.9)])
        #expect(snapped[0].range.end.seconds <= snapped[1].range.start.seconds + 0.0001)
        #expect(snapped[0].range.start.seconds < snapped[0].range.end.seconds)
    }

    @Test func voiceWithoutWordsIsFoundButBreathIsNot() {
        let sound = activity([
            (0.2, 0.6, -20),   // "so"
            (1.0, 1.3, -24),   // "ııı", not written down
            (1.6, 1.9, -60),   // a breath
            (2.4, 2.9, -20),   // "right"
        ])
        let found = sound.unheardSounds(between: [word("so", 0.2, 0.6), word("right", 2.4, 2.9)])
        #expect(found.count == 1)
        #expect(abs((found.first?.lowerBound ?? 0) - 1.0) < 0.03)
        #expect(abs((found.first?.upperBound ?? 0) - 1.3) < 0.03)

        // A sound that was written down is not unheard.
        let written = sound.unheardSounds(between: [word("so", 0.2, 0.6), word("um", 1.0, 1.3), word("right", 2.4, 2.9)])
        #expect(written.isEmpty)
    }
}
