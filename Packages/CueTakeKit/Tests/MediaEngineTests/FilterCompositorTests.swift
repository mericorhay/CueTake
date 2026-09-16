import CoreImage
import CoreMedia
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

    @Test func transitionRegionHandsTheTracksOverAtTheCut() {
        let region = TransitionRegion(
            start: CMTime(value: 1200, timescale: 600),
            cut: CMTime(value: 1500, timescale: 600),
            end: CMTime(value: 1800, timescale: 600),
            kind: .crossfade,
            mainTrackID: 1,
            carrierTrackID: 3
        )
        let before = CMTime(value: 1300, timescale: 600)
        let after = CMTime(value: 1600, timescale: 600)

        #expect(region.contains(before))
        #expect(!region.contains(CMTime(value: 1800, timescale: 600)))
        #expect(region.tracks(at: before).outgoing == 1)
        #expect(region.tracks(at: before).incoming == 3)
        #expect(region.tracks(at: after).outgoing == 3)
        #expect(region.tracks(at: after).incoming == 1)
        #expect(region.look(at: region.start).outgoing.opacity == 1)
        #expect(region.look(at: region.end).outgoing.opacity == 0)
    }

    @Test func transitionMovementIsDrawnInRenderSpace() throws {
        let size = CGSize(width: 100, height: 200)
        let frame = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(origin: .zero, size: size))

        var half = TransitionLook.Layer()
        half.scale = 0.5
        let scaled = try #require(FilterCompositor.apply(half, to: frame, in: size))
        #expect(scaled.extent == CGRect(x: 25, y: 50, width: 50, height: 100))

        // Down in the look is down on screen: towards zero in Core Image.
        var lowered = TransitionLook.Layer()
        lowered.dy = 0.5
        let moved = try #require(FilterCompositor.apply(lowered, to: frame, in: size))
        #expect(moved.extent.minY == -100)

        // The top quarter only.
        var top = TransitionLook.Layer()
        top.visible = TransitionLook.Region(0, 0, 1, 0.25)
        let cropped = try #require(FilterCompositor.apply(top, to: frame, in: size))
        #expect(cropped.extent == CGRect(x: 0, y: 150, width: 100, height: 50))

        var gone = TransitionLook.Layer()
        gone.opacity = 0
        #expect(FilterCompositor.apply(gone, to: frame, in: size) == nil)
        var wiped = TransitionLook.Layer()
        wiped.visible = TransitionLook.Region(0, 0, 0, 1)
        #expect(FilterCompositor.apply(wiped, to: frame, in: size) == nil)

        #expect(FilterCompositor.apply(TransitionLook.Layer(), to: frame, in: size)?.extent == frame.extent)
    }
}
