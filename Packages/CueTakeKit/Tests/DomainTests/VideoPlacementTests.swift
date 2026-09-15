import Domain
import Foundation
import Testing

struct VideoPlacementTests {
    @Test func olderPlacementsDecodeWithCenteredFocus() throws {
        let json = #"{"x":0,"y":0,"width":1,"height":1,"fillsFrame":true,"isMirrored":false,"opacity":1}"#
        let placement = try JSONDecoder().decode(VideoPlacement.self, from: Data(json.utf8))

        #expect(placement.focusX == nil)
        #expect(placement.focusY == nil)
    }

    @Test func focusInterpolatesAndStaysInsideTheSource() {
        let start = VideoPlacement(fillsFrame: true, focusX: 0.1, focusY: 0.2)
        let end = VideoPlacement(fillsFrame: true, focusX: 1.4, focusY: -0.3)
        let middle = start.interpolated(to: end, fraction: 0.5)

        #expect(abs((middle.focusX ?? 0) - 0.55) < 0.001)
        #expect(abs((middle.focusY ?? 0) - 0.1) < 0.001)
    }

    @Test func trackingDoesNotAnimateTheLayerRectangle() {
        var layer = VideoLayer(
            recordingID: UUID(),
            title: "Tracked",
            sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 10)),
            placement: VideoPlacement(x: 0.1, y: 0.2, width: 0.4, height: 0.3, fillsFrame: true)
        )
        layer.focusKeyframes = [
            VideoFocusKeyframe(time: 0, x: 0.2, y: 0.5),
            VideoFocusKeyframe(time: 10, x: 0.8, y: 0.5),
        ]

        let middle = layer.placement(at: 5)
        #expect(abs(middle.x - 0.1) < 0.001)
        #expect(abs(middle.y - 0.2) < 0.001)
        #expect(abs(middle.width - 0.4) < 0.001)
        #expect(abs((middle.focusX ?? 0) - 0.5) < 0.001)
    }

    @Test func olderFocusFramesDecodeWithoutInventingAWarning() throws {
        let id = UUID()
        let json = #"{"id":"\#(id.uuidString)","time":1.5,"x":0.4,"y":0.6}"#
        let frame = try JSONDecoder().decode(VideoFocusKeyframe.self, from: Data(json.utf8))

        #expect(frame.confidence == nil)
        #expect(frame.zoom == nil)
    }

    @Test func build54TrackingMigratesAwayFromPlacementAnimation() {
        var layer = VideoLayer(
            recordingID: UUID(),
            title: "Legacy",
            sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 10)),
            placement: VideoPlacement(x: 0.1, y: 0.2, width: 0.4, height: 0.3, fillsFrame: true, focusX: 0.2, focusY: 0.5)
        )
        layer.keyframes = [
            VideoKeyframe(time: 5, placement: VideoPlacement(x: 0.1, y: 0.2, width: 0.4, height: 0.3, fillsFrame: true, focusX: 0.8, focusY: 0.5)),
        ]

        layer.separateLegacyTracking()

        #expect(layer.keyframes.isEmpty)
        #expect(layer.focusKeyframes?.count == 2)
        #expect(layer.placement.focusX == nil)
        #expect(abs(layer.placement(at: 5).x - 0.1) < 0.001)
    }
}
