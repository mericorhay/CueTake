import Foundation
import Testing
@testable import Domain
@testable import MediaEngine

/// The music volume curve. AVFoundation raises an uncatchable exception on overlapping ramps, so
/// "the ramps never overlap" is not a nicety here — it is the difference between a mix and a crash.
struct AudioEnvelopeTests {
    private func clip(
        start: Double = 0,
        length: Double = 20,
        gain: Double = 0.5,
        fadeIn: Double = 1,
        fadeOut: Double = 2,
        ducks: Bool = true,
        muted: Bool = false
    ) -> AudioClip {
        AudioClip(
            name: "music",
            relativePath: "media/m.m4a",
            start: MediaTime(seconds: start),
            sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: length)),
            gain: gain,
            fadeIn: MediaTime(seconds: fadeIn),
            fadeOut: MediaTime(seconds: fadeOut),
            isMuted: muted,
            ducksUnderVoice: ducks
        )
    }

    private func range(_ start: Double, _ duration: Double) -> MediaTimeRange {
        MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: duration))
    }

    private func assertContiguous(_ ramps: [AudioEnvelope.Ramp], length: Double) {
        #expect(ramps.first?.start == 0)
        for (a, b) in zip(ramps, ramps.dropFirst()) {
            #expect(abs((a.start + a.duration) - b.start) < 0.0001, "ramps must meet exactly, never overlap")
            #expect(a.duration > 0)
        }
        if let last = ramps.last {
            #expect(abs(last.start + last.duration - length) < 0.0001)
        }
    }

    @Test func fadesStartAndEndSilentAtGain() {
        let ramps = AudioEnvelope.ramps(for: clip(ducks: false), spoken: [])
        assertContiguous(ramps, length: 20)
        #expect(ramps.first?.from == 0)
        #expect(ramps.first?.to == 0.5)
        #expect(ramps.last?.to == 0)
    }

    @Test func duckingDropsUnderSpeech() {
        let ramps = AudioEnvelope.ramps(for: clip(), spoken: [range(5, 4)])
        assertContiguous(ramps, length: 20)
        let lowest = ramps.map { min($0.from, $0.to) }.filter { $0 > 0 }.min() ?? 1
        #expect(abs(lowest - 0.5 * AudioEnvelope.duckLevel) < 0.0001)
    }

    @Test func closeSentencesShareOneDuck() {
        // Two sentences a quarter second apart: one dip, not a bounce between them.
        let ramps = AudioEnvelope.ramps(for: clip(ducks: true), spoken: [range(5, 2), range(7.25, 2)])
        assertContiguous(ramps, length: 20)
        let rises = zip(ramps, ramps.dropFirst()).filter { $0.0.to < $0.1.to && $0.0.to < 0.5 }
        #expect(rises.count == 1)
    }

    @Test func speechOutsideTheClipIsIgnored() {
        let ramps = AudioEnvelope.ramps(for: clip(start: 30), spoken: [range(5, 4)])
        #expect(ramps.allSatisfy { $0.from >= 0 && $0.to >= 0 })
        #expect(!ramps.contains { abs($0.to - 0.5 * AudioEnvelope.duckLevel) < 0.0001 })
    }

    @Test func mutedIsSilentThroughout() {
        let ramps = AudioEnvelope.ramps(for: clip(muted: true), spoken: [range(5, 4)])
        #expect(ramps.allSatisfy { $0.from == 0 && $0.to == 0 })
    }
    // MARK: - Drawn volume

    /// The curve's value at a moment, read back from the ramps.
    private func level(at t: Double, in ramps: [AudioEnvelope.Ramp]) -> Double? {
        guard let ramp = ramps.first(where: { t >= $0.start && t <= $0.start + $0.duration }) else { return nil }
        let fraction = ramp.duration > 0 ? (t - ramp.start) / ramp.duration : 0
        return ramp.from + (ramp.to - ramp.from) * fraction
    }

    @Test func aClipNobodyDrewOnKeepsItsCurveExactly() {
        let plain = clip()
        var drawn = clip()
        drawn.volumeKeys = []
        let spoken = [range(5, 3)]
        #expect(AudioEnvelope.ramps(for: plain, spoken: spoken) == AudioEnvelope.ramps(for: drawn, spoken: spoken))
    }

    @Test func keysMultiplyTheFadesInsteadOfReplacingThem() {
        var music = clip(gain: 1, fadeIn: 1, fadeOut: 2, ducks: false)
        music.setVolumeKey(at: 6, level: 1)
        music.setVolumeKey(at: 10, level: 0.5)
        let ramps = AudioEnvelope.ramps(for: music, spoken: [])
        assertContiguous(ramps, length: 20)

        // Before the first key the drawn level is 1: the fade in is untouched.
        #expect(abs((level(at: 0, in: ramps) ?? -1) - 0) < 0.001)
        #expect(abs((level(at: 1, in: ramps) ?? -1) - 1) < 0.001)
        // Half way down the drawn slope, and flat at half after it…
        #expect(abs((level(at: 8, in: ramps) ?? -1) - 0.75) < 0.001)
        #expect(abs((level(at: 14, in: ramps) ?? -1) - 0.5) < 0.001)
        // …and the fade out still ends in silence.
        #expect(abs((level(at: 20, in: ramps) ?? -1) - 0) < 0.001)
    }

    @Test func aKeyDoesNotSwitchTheDuckingOff() {
        var music = clip(gain: 1, fadeIn: 0, fadeOut: 0, ducks: true)
        music.setVolumeKey(at: 0, level: 2)
        music.setVolumeKey(at: 20, level: 2)
        let ramps = AudioEnvelope.ramps(for: music, spoken: [range(8, 4)])
        // Under the voice the music is still ducked — twice the duck level, since the key doubles it.
        let underVoice = level(at: 10, in: ramps) ?? -1
        #expect(abs(underVoice - AudioEnvelope.duckLevel * 2) < 0.001)
        #expect(abs((level(at: 2, in: ramps) ?? -1) - 2) < 0.001)
    }
}
