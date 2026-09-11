import Foundation
import Testing
@testable import Domain

struct TimelineBuilderTests {
    let recordingID = UUID()

    func readyTake(seconds: Double) -> Take {
        Take(
            recordingID: recordingID,
            sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: seconds)),
            status: .ready
        )
    }

    func project(durations: [Double]) -> Project {
        var project = Project(title: "Test", localeIdentifier: "tr-TR")
        project.segments = durations.map { seconds in
            let take = readyTake(seconds: seconds)
            return Segment(role: .mainPoint, script: "x", takes: [take], selectedTakeID: take.id)
        }
        return project
    }

    @Test func clipsAreLaidOutEndToEnd() {
        let timeline = TimelineBuilder.build(from: project(durations: [2, 3, 4]))

        #expect(timeline.clips.map(\.timelineRange.start) == [.zero, MediaTime(seconds: 2), MediaTime(seconds: 5)])
        #expect(timeline.duration == MediaTime(seconds: 9))
    }

    @Test func retakeTouchesOnlyItsSegmentAndLaterClipsFollow() throws {
        var project = project(durations: [2, 3, 4])
        let third = project.segments[2]
        project.segments[2].captions = [
            CaptionCue(text: "hi", range: MediaTimeRange(start: MediaTime(seconds: 1), duration: MediaTime(seconds: 1)))
        ]

        try project.addTake(readyTake(seconds: 5), toSegment: project.segments[1].id)
        let timeline = TimelineBuilder.build(from: project)

        #expect(project.segments[1].takes.count == 2)
        #expect(project.segments[2] == third.withCaptions(project.segments[2].captions))
        #expect(timeline.clip(for: third.id)?.timelineRange.start == MediaTime(seconds: 7))
        #expect(timeline.captions.first?.timelineRange.start == MediaTime(seconds: 8))
    }

    @Test func segmentsWithoutReadyTakeAreReportedMissing() {
        var project = project(durations: [2, 3])
        project.segments.append(Segment(role: .callToAction, script: "Follow"))

        let timeline = TimelineBuilder.build(from: project)

        #expect(timeline.missingSegmentIDs == [project.segments[2].id])
        #expect(timeline.duration == MediaTime(seconds: 5))
    }
}

private extension Segment {
    func withCaptions(_ captions: [CaptionCue]) -> Segment {
        var copy = self
        copy.captions = captions
        return copy
    }
}
