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

    @Test func zoomKeepsTheFocusButConsumesMoreOfTheSource() {
        let size = CGSize(width: 1920, height: 1080)
        let render = CGSize(width: 1080, height: 1920)
        let regular = VideoFrameGeometry(
            natural: size,
            preferred: .identity,
            placement: VideoPlacement(fillsFrame: true, focusX: 0.65, focusY: 0.5),
            render: render
        )
        let zoomed = VideoFrameGeometry(
            natural: size,
            preferred: .identity,
            placement: VideoPlacement(fillsFrame: true, zoom: 1.2, focusX: 0.65, focusY: 0.5),
            render: render
        )

        #expect(zoomed.crop.width < regular.crop.width)
        #expect(zoomed.crop.height < regular.crop.height)
        #expect(zoomed.crop.midX > regular.crop.midX - 1)
    }

    @Test func cameraMotionAddsTravelOnTopOfTrackedFraming() {
        let motion = CameraMotionRecipe(
            sourceRange: MediaTimeRange(start: MediaTime(seconds: 3), duration: MediaTime(seconds: 10)),
            amount: 0.2,
            kind: .pushIn
        )
        let focuses = [
            VideoFocusKeyframe(time: 3, x: 0.45, y: 0.5, zoom: 1.15),
            VideoFocusKeyframe(time: 13, x: 0.55, y: 0.5, zoom: 1.15),
        ]

        let placement = VideoComposer.mainPlacement(
            .full,
            focuses: focuses,
            cameraMotions: [motion],
            takeStart: 3,
            takeLength: 10,
            playback: .normal,
            timelineTime: 5
        )

        #expect(abs((placement.zoom ?? 0) - 1.25) < 0.001)
        #expect(placement.fillsFrame)
        #expect(abs((placement.focusX ?? 0) - 0.5) < 0.001)
    }

    @Test func aShortenedTrackEasesBackToTheCentre() {
        let focuses = [
            VideoFocusKeyframe(time: 5, x: 0.2, y: 0.5),
            VideoFocusKeyframe(time: 8, x: 0.2, y: 0.5),
        ]
        func focusX(at timeline: Double) -> Double {
            VideoComposer.mainPlacement(
                .full,
                focuses: focuses,
                cameraMotions: [],
                takeStart: 3,
                takeLength: 10,
                playback: .normal,
                timelineTime: timeline
            ).focusX ?? 0.5
        }
        #expect(abs(focusX(at: 3) - 0.2) < 0.001)
        #expect(focusX(at: 1.9) > 0.2 && focusX(at: 1.9) < 0.5)
        #expect(abs(focusX(at: 0.5) - 0.5) < 0.001)
        #expect(abs(focusX(at: 9) - 0.5) < 0.001)
    }

    @Test func mainVideoFillsTheFrameUnlessThatCutsAwayTooMuch() {
        let render = CGSize(width: 1080, height: 1920)
        // Shot 3:4: filling keeps 75% of it, which beats a picture in black bars.
        let photo = VideoComposer.framed(.full, natural: CGSize(width: 1440, height: 1920), preferred: .identity, render: render)
        #expect(photo.fillsFrame)
        // A portrait recording stored sideways is still portrait.
        let rotated = VideoComposer.framed(
            .full,
            natural: CGSize(width: 1920, height: 1080),
            preferred: CGAffineTransform(rotationAngle: .pi / 2),
            render: render
        )
        #expect(rotated.fillsFrame)
        // Landscape in a vertical video would keep a third: fitted.
        let landscape = VideoComposer.framed(.full, natural: CGSize(width: 1920, height: 1080), preferred: .identity, render: render)
        #expect(!landscape.fillsFrame)
        // A choice already made is kept.
        let chosen = VideoComposer.framed(VideoPlacement(fillsFrame: true), natural: CGSize(width: 1920, height: 1080), preferred: .identity, render: render)
        #expect(chosen.fillsFrame)
    }
}
