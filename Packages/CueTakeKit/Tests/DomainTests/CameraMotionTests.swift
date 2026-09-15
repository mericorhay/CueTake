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
}
