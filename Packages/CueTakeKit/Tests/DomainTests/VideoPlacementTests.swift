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
}
