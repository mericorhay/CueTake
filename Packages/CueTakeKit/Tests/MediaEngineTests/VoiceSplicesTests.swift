import Foundation
import Testing
@testable import MediaEngine

struct VoiceSplicesTests {
    private func ranges(_ steps: [VoiceSplices.Step]) -> [(start: Double, end: Double)] {
        steps.compactMap { step in
            if case .ramp(_, _, let start, let end) = step { return (start, end) }
            return nil
        }
    }

    @Test func everyJoinDipsAndRampsNeverOverlap() {
        let steps = VoiceSplices.envelope(levels: [(0, 1), (3, 1), (6, 0.5)])
        #expect(steps.first == .set(at: 0, value: 1))
        let ramps = ranges(steps)
        #expect(ramps.count == 4)
        for (a, b) in zip(ramps, ramps.dropFirst()) {
            #expect(a.end <= b.start + 0.000_001)
        }
        guard case .ramp(let from, let to, _, let end) = steps.last else {
            Issue.record("the last step should rise to the new level")
            return
        }
        #expect(from == 0)
        #expect(to == 0.5)
        #expect(abs(end - 6.008) < 0.0001)
    }

    @Test func joinsCloseTogetherStillDoNotOverlap() {
        let steps = VoiceSplices.envelope(levels: [(0, 1), (2, 1), (2.01, 0.5), (2.012, 1), (5, 0)])
        let ramps = ranges(steps)
        for (a, b) in zip(ramps, ramps.dropFirst()) {
            #expect(a.end <= b.start + 0.000_001)
        }
        for ramp in ramps {
            #expect(ramp.end > ramp.start)
        }
        // Silence after the last join is set, not ramped up to.
        #expect(steps.last == .set(at: 5, value: 0))
    }

    @Test func aSingleLevelIsHeld() {
        #expect(VoiceSplices.envelope(levels: [(0, 1)]) == [.set(at: 0, value: 1)])
        #expect(VoiceSplices.envelope(levels: []) == [])
    }
}
