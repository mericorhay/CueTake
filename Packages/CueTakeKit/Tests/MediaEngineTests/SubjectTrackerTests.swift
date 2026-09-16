import CoreGraphics
import Testing
@testable import MediaEngine

struct SubjectTrackerTests {
    @Test func reductionCollapsesDuplicateReviewSamples() {
        let reduced = SubjectTracker.reduce([
            SubjectFocus(time: 0, x: 0.5, y: 0.5, confidence: 0.9),
            SubjectFocus(time: 0.5, x: 0.5, y: 0.5, confidence: 0.2, state: .searching),
            SubjectFocus(time: 0.5, x: 0.5, y: 0.5, confidence: 0.1, state: .searching),
            SubjectFocus(time: 1, x: 0.5, y: 0.5, confidence: 0.9),
        ])

        #expect(reduced.map(\.time) == [0, 0.5, 1])
        #expect(reduced[1].confidence == 0.1)
    }

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

    @Test func reductionKeepsSearchingAndReacquiredEdges() {
        let points = [
            SubjectFocus(time: 0, x: 0.5, y: 0.5, confidence: 0.92),
            SubjectFocus(time: 0.5, x: 0.5, y: 0.5, confidence: 0, state: .searching),
            SubjectFocus(time: 1, x: 0.51, y: 0.5, confidence: 0.81, state: .reacquired),
            SubjectFocus(time: 1.5, x: 0.51, y: 0.5, confidence: 0.9),
        ]

        let reduced = SubjectTracker.reduce(points)

        #expect(reduced.map(\.state) == [.tracking, .searching, .reacquired, .tracking])
    }

    @Test func recoveryRejectsAVisuallyDifferentCandidate() {
        let predicted = CGRect(x: 0.4, y: 0.4, width: 0.16, height: 0.2)
        let candidate = CGRect(x: 0.42, y: 0.4, width: 0.16, height: 0.2)

        let score = SubjectRecoveryPolicy.score(
            candidate: candidate,
            predicted: predicted,
            appearanceDistance: 0.72,
            missedFrames: 3
        )

        #expect(score == nil)
    }

    @Test func recoveryExpandsSearchAfterAnOcclusion() {
        let predicted = CGRect(x: 0.08, y: 0.4, width: 0.12, height: 0.16)
        let reentered = CGRect(x: 0.46, y: 0.4, width: 0.12, height: 0.16)

        let early = SubjectRecoveryPolicy.score(
            candidate: reentered,
            predicted: predicted,
            appearanceDistance: 0.18,
            missedFrames: 0
        )
        let afterOcclusion = SubjectRecoveryPolicy.score(
            candidate: reentered,
            predicted: predicted,
            appearanceDistance: 0.18,
            missedFrames: 8
        )

        #expect(early == nil)
        #expect(afterOcclusion != nil)
    }

    @Test func recoveryRejectsAnImplausibleScaleJump() {
        let predicted = CGRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1)
        let candidate = CGRect(x: 0.25, y: 0.25, width: 0.55, height: 0.55)

        let score = SubjectRecoveryPolicy.score(
            candidate: candidate,
            predicted: predicted,
            appearanceDistance: 0.12,
            missedFrames: 8
        )

        #expect(score == nil)
    }

    @Test func predictionCarriesRecentMotionForward() {
        let previous = CGRect(x: 0.2, y: 0.3, width: 0.15, height: 0.2)
        let last = CGRect(x: 0.25, y: 0.27, width: 0.15, height: 0.2)

        let predicted = SubjectRecoveryPolicy.predictedBounds(last: last, previous: previous)

        #expect(abs(predicted.minX - 0.3) < 0.0001)
        #expect(abs(predicted.minY - 0.24) < 0.0001)
        #expect(predicted.size == last.size)
    }
}
