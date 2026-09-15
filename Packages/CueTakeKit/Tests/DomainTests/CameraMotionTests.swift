import Foundation
import Testing
@testable import Domain

struct CameraMotionTests {
    private let range = MediaTimeRange(start: MediaTime(seconds: 2), duration: MediaTime(seconds: 4))

    @Test func pushInStartsAtOneAndEndsAtRequestedZoom() {
        let move = CameraMotionRecipe(sourceRange: range, amount: 0.2, kind: .pushIn)
        #expect(abs(CameraMotionEvaluator.zoom(at: 2, recipes: [move]) - 1) < 0.0001)
        #expect(abs(CameraMotionEvaluator.zoom(at: 6, recipes: [move]) - 1.2) < 0.0001)
    }

    @Test func punchReturnsToTheOriginalFrame() {
        let move = CameraMotionRecipe(sourceRange: range, amount: 0.15, kind: .punch)
        #expect(abs(CameraMotionEvaluator.zoom(at: 2, recipes: [move]) - 1) < 0.0001)
        #expect(CameraMotionEvaluator.zoom(at: 4, recipes: [move]) > 1.14)
        #expect(abs(CameraMotionEvaluator.zoom(at: 6, recipes: [move]) - 1) < 0.0001)
    }

    @Test func recipeUsesSourceTimeAndDoesNothingOutsideItsRange() {
        let move = CameraMotionRecipe(sourceRange: range, amount: 0.2, kind: .pullOut)
        #expect(CameraMotionEvaluator.zoom(at: 1.99, recipes: [move]) == 1)
        #expect(CameraMotionEvaluator.zoom(at: 6.01, recipes: [move]) == 1)
    }

    @Test func sourceClockHandlesReverseAndFreezeWithoutDrift() {
        let reversed = ClipPlayback(speed: 2, isReversed: true)
        #expect(abs(reversed.sourceOffset(forTimeline: 1, sourceLength: 8) - 6) < 0.0001)
        #expect(abs((reversed.timelineOffset(forSourceOffset: 6, sourceLength: 8) ?? -1) - 1) < 0.0001)

        let frozen = ClipPlayback(freeze: MediaTime(seconds: 4))
        #expect(frozen.sourceOffset(forTimeline: 3.8, sourceLength: 8) == 0)
        #expect(frozen.timelineOffset(forSourceOffset: 2, sourceLength: 8) == nil)
    }

    @Test func heldZoomStaysConstantAcrossTheClip() {
        let hold = CameraMotionRecipe(sourceRange: range, amount: 0.15, kind: .hold)
        #expect(abs(CameraMotionEvaluator.zoom(at: 2, recipes: [hold]) - 1.15) < 0.0001)
        #expect(abs(CameraMotionEvaluator.zoom(at: 4, recipes: [hold]) - 1.15) < 0.0001)
        #expect(abs(CameraMotionEvaluator.zoom(at: 6, recipes: [hold]) - 1.15) < 0.0001)
    }

    @Test func cameraTravelStartsFromTrackingCrop() {
        let move = CameraMotionRecipe(sourceRange: range, amount: 0.15, kind: .pushIn)
        #expect(abs(CameraMotionEvaluator.combinedZoom(baseZoom: 1.15, at: 2, recipes: [move]) - 1.15) < 0.0001)
        #expect(abs(CameraMotionEvaluator.combinedZoom(baseZoom: 1.15, at: 6, recipes: [move]) - 1.30) < 0.0001)
    }
}
