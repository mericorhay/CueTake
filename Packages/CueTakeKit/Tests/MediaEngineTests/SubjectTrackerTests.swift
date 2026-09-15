import Testing
@testable import MediaEngine

struct SubjectTrackerTests {
    @Test func reductionKeepsAConfidenceDipEvenWhenSubjectIsStill() {
        let points = [
            SubjectFocus(time: 0, x: 0.5, y: 0.5, confidence: 0.95),
            SubjectFocus(time: 0.5, x: 0.501, y: 0.501, confidence: 0.42),
            SubjectFocus(time: 1, x: 0.502, y: 0.502, confidence: 0.93),
        ]

        let reduced = SubjectTracker.reduce(points)

        #expect(reduced.count == 3)
        #expect(reduced[1].confidence == 0.42)
    }
}
