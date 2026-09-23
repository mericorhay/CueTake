import Foundation
import Testing
@testable import MediaEngine

/// Beats found in a drum loop made here: kicks on the beat, hi-hats between. The grid has to land
/// on the kicks, not the hi-hats, and hold its tempo for the whole loop.
struct BeatDetectorTests {
    private func loop(bpm: Double, seconds: Double = 30, offset: Double = 0.23) -> [Float] {
        let rate = BeatDetector.analysisRate
        var samples = [Float](repeating: 0, count: Int(rate * seconds))
        var seed: UInt64 = 7
        func noise() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int64(bitPattern: seed)) / Float(Int64.max)
        }
        for i in samples.indices { samples[i] = noise() * 0.02 }
        let period = 60 / bpm
        var time = offset
        var beat = 0
        while time < seconds - 0.3 {
            let start = Int(time * rate)
            let amplitude: Float = beat % 4 == 0 ? 1 : 0.6
            for n in 0..<Int(0.15 * rate) where start + n < samples.count {
                let t = Double(n) / rate
                samples[start + n] += amplitude * Float(sin(2 * .pi * (50 + 80 * exp(-t * 30)) * t) * exp(-t * 18))
            }
            let hat = Int((time + period / 2) * rate)
            for n in 0..<400 where hat + n < samples.count {
                samples[hat + n] += noise() * 0.15 * Float(exp(-Double(n) / 80))
            }
            time += period
            beat += 1
        }
        return samples
    }

    @Test(arguments: [82.0, 110.0, 128.0, 150.0])
    func landsOnTheKicks(bpm: Double) throws {
        let grid = try #require(BeatDetector.grid(samples: loop(bpm: bpm), sampleRate: BeatDetector.analysisRate))
        #expect(abs(grid.bpm - bpm) < 1.5)
        let period = 60 / bpm
        let errors = grid.beats.dropFirst().dropLast().map { time -> Double in
            let phase = (time - 0.23) / period
            return abs(phase - phase.rounded()) * period
        }.sorted()
        #expect(errors[errors.count / 2] < 0.04)
        #expect(grid.downbeats.count >= grid.beats.count / 4 - 1)
    }
}
