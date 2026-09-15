import CoreVideo
import Domain
import Foundation
import Testing
@testable import MediaEngine

struct FilterCompositorTests {
    @Test func renderDestinationUsesOneConcretePixelFormat() {
        let value = FilterCompositor()
            .requiredPixelBufferAttributesForRenderContext[kCVPixelBufferPixelFormatTypeKey as String]

        #expect(value as? OSType == kCVPixelFormatType_32BGRA)
    }

    @Test func liveFiltersFollowTheirTimelineSpanAndRefresh() {
        let warm = TimelineEffect(
            start: MediaTime(seconds: 1),
            duration: MediaTime(seconds: 2),
            kind: .filter(FilterSettings(look: .warm))
        )
        let filters = LiveFilters([warm])

        #expect(filters.settings(at: 0.99).isEmpty)
        #expect(filters.settings(at: 1).first?.look == .warm)
        #expect(filters.settings(at: 2.99).first?.look == .warm)
        #expect(filters.settings(at: 3).isEmpty)

        let noir = TimelineEffect(
            start: .zero,
            duration: MediaTime(seconds: 5),
            kind: .filter(FilterSettings(look: .noir))
        )
        filters.update([noir])
        #expect(filters.settings(at: 2).map(\.look) == [.noir])
    }
}
