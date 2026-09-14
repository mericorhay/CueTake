import CoreGraphics
import Domain
import Testing
@testable import MediaEngine

struct VideoFrameGeometryTests {
    @Test func smartFocusMovesTheCropInsideAFixedPortraitFrame() {
        let size = CGSize(width: 1920, height: 1080)
        let render = CGSize(width: 1080, height: 1920)
        let centered = VideoFrameGeometry(
            natural: size,
            preferred: .identity,
            placement: VideoPlacement(fillsFrame: true),
            render: render
        )
        let left = VideoFrameGeometry(
            natural: size,
            preferred: .identity,
            placement: VideoPlacement(fillsFrame: true, focusX: 0.25, focusY: 0.5),
            render: render
        )
        let edge = VideoFrameGeometry(
            natural: size,
            preferred: .identity,
            placement: VideoPlacement(fillsFrame: true, focusX: 0, focusY: 0.5),
            render: render
        )

        #expect(abs(left.crop.width - centered.crop.width) < 0.001)
        #expect(left.crop.minX < centered.crop.minX)
        #expect(abs(edge.crop.width - centered.crop.width) < 0.001)
        #expect(edge.crop.minX >= 0)
    }

    @Test func trackerDropsJitterButKeepsRealMovementAndTheEnd() {
        let reduced = SubjectTracker.reduce([
            SubjectFocus(time: 0, x: 0.50, y: 0.50, confidence: 0.9),
            SubjectFocus(time: 0.5, x: 0.505, y: 0.504, confidence: 0.9),
            SubjectFocus(time: 1, x: 0.62, y: 0.50, confidence: 0.9),
            SubjectFocus(time: 1.5, x: 0.621, y: 0.50, confidence: 0.9),
        ])

        #expect(reduced.map(\.time) == [0, 1, 1.5])
    }
}
