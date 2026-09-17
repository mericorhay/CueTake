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

    @Test func transitionFilmsSitCentredOnTheirCutsAndFollowTheEdit() throws {
        let recording = Recording(relativePath: "a.mov", format: .vertical1080, camera: .back, duration: MediaTime(seconds: 20))
        func segment(_ start: Double, _ length: Double) -> Segment {
            var segment = Segment(role: .hook, script: "")
            let take = Take(recordingID: recording.id, sourceRange: MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: length)), status: .ready)
            segment.takes = [take]
            segment.selectedTakeID = take.id
            return segment
        }
        var project = Project(title: "t", localeIdentifier: "en-US", segments: [segment(0, 4), segment(4, 6)], recordings: [recording])
        let folder = URL(filePath: NSTemporaryDirectory())
        #expect(TransitionRenderer.jobs(for: project, in: folder).isEmpty)

        project.setTransition(after: project.segments[0].id, kind: .crossfade, duration: 1)
        let jobs = TransitionRenderer.jobs(for: project, in: folder)
        let job = try #require(jobs.first)
        #expect(jobs.count == 1)
        #expect(abs(job.cut - project.segments[0].barWeight) < 0.0001)
        #expect(abs(job.start - (job.cut - 0.5)) < 0.0001)
        #expect(abs(job.end - (job.cut + 0.5)) < 0.0001)

        // Captions and titles do not redraw it; the picture does.
        var renamed = project
        renamed.title = "other"
        #expect(TransitionRenderer.jobs(for: renamed, in: folder).first?.name == job.name)
        var reframed = project
        reframed.mainVideoPlacement.zoom = 1.2
        #expect(TransitionRenderer.jobs(for: reframed, in: folder).first?.name != job.name)

        // Not written yet: the composer plays the cut as a cut and adds nothing.
        let layered = TransitionRenderer.layered(project, in: folder)
        #expect(layered.transitions.isEmpty)
        #expect(layered.videoLayers.isEmpty)
    }
}
