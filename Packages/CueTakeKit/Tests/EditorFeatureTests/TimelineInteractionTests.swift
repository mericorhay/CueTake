import Domain
import Foundation
import Testing
@testable import EditorFeature

struct TimelineInteractionTests {
    @Test func overviewScaleStillAllowsNearbyFrames() {
        #expect(TimelineScale.fit >= 30)
        #expect(TimelineScale.snapTolerance(pointsPerSecond: TimelineScale.fit) <= 0.12)
        #expect(TimelineScale.snapTolerance(pointsPerSecond: TimelineScale.minimum) <= 0.12)
    }

    @Test func reviewCountsLostEpisodesInsteadOfEverySample() {
        let points = [
            point(time: 0, confidence: 0.9),
            point(time: 0.1, confidence: 0.1, state: .searching),
            point(time: 0.2, confidence: 0.2, state: .searching),
            point(time: 0.3, confidence: 0.55, state: .reacquired),
            // A weak frame the engine still vouched for is not a problem.
            point(time: 1, confidence: 0.2),
            point(time: 1.1, confidence: 0.9),
            // Nor is a single lost frame between good ones.
            point(time: 1.5, confidence: 0.1, state: .searching),
            point(time: 1.6, confidence: 0.9),
        ]

        let issues = SubjectTrackReviewPoint.reviewIssues(in: points)

        #expect(issues.map(\.timelineTime) == [0.1])
    }

    private func point(
        time: Double,
        confidence: Double,
        state: VideoFocusTrackingState? = .tracking
    ) -> SubjectTrackReviewPoint {
        SubjectTrackReviewPoint(
            id: UUID(),
            timelineTime: time,
            confidence: confidence,
            progress: time / 2,
            trackingState: state
        )
    }
}
