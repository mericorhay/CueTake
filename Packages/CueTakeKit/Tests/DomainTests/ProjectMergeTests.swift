import Foundation
import Testing
@testable import Domain

/// Two phones editing one project. Each test is a thing two real people would do in the same
/// minute, and what both of them should see afterwards.
struct ProjectMergeTests {
    private let recording = Recording(relativePath: "media/a.mov", format: .vertical1080, camera: .front, duration: MediaTime(seconds: 60))

    private func segment(_ script: String, at second: Double) -> Segment {
        let take = Take(
            recordingID: recording.id,
            sourceRange: MediaTimeRange(start: MediaTime(seconds: second), duration: MediaTime(seconds: 3)),
            status: .ready
        )
        return Segment(role: .mainPoint, script: script, takes: [take], selectedTakeID: take.id)
    }

    private func base() -> Project {
        Project(
            title: "Kahve",
            localeIdentifier: "tr-TR",
            segments: [segment("bir", at: 0), segment("iki", at: 3), segment("üç", at: 6)],
            recordings: [recording]
        )
    }

    private func scripts(_ project: Project) -> [String] {
        project.segments.map { $0.script }
    }

    @Test func aTitleOnlyOneSideChangedTakesThatSide() {
        let start = base()
        var mine = start
        var theirs = start
        theirs.title = "Kahve Lab"
        #expect(ProjectMerge.merge(base: start, mine: mine, theirs: theirs).project.title == "Kahve Lab")

        mine.title = "Benim"
        theirs.title = start.title
        #expect(ProjectMerge.merge(base: start, mine: mine, theirs: theirs).project.title == "Benim")
    }

    @Test func bothChangingTheTitleKeepsMineAndSaysSo() {
        let start = base()
        var mine = start
        var theirs = start
        mine.title = "Benim"
        theirs.title = "Onların"
        let merged = ProjectMerge.merge(base: start, mine: mine, theirs: theirs)
        #expect(merged.project.title == "Benim")
        let fields = merged.collisions.map { $0.field }
        #expect(fields == ["title"])
    }

    @Test func twoPeopleEditingTwoClipsBothKeepTheirWork() {
        let start = base()
        var mine = start
        var theirs = start
        mine.segments[0].script = "bir — benim"
        theirs.segments[2].script = "üç — onların"
        let merged = ProjectMerge.merge(base: start, mine: mine, theirs: theirs)
        #expect(scripts(merged.project) == ["bir — benim", "iki", "üç — onların"])
        #expect(merged.collisions.isEmpty)
    }

    @Test func thingsAddedOnBothSidesAreAllThere() {
        let start = base()
        var mine = start
        var theirs = start
        mine.overlays.append(Overlay(content: .text(OverlayText(text: "benim")), start: .zero))
        theirs.overlays.append(Overlay(content: .text(OverlayText(text: "onların")), start: MediaTime(seconds: 2)))
        theirs.audio.append(AudioClip(name: "müzik", relativePath: "media/m.m4a", sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 9))))
        let merged = ProjectMerge.merge(base: start, mine: mine, theirs: theirs).project
        #expect(merged.overlays.count == 2)
        #expect(merged.audio.count == 1)
    }

    @Test func aClipIDeletedWhileTheyEditedItIsKeptWithTheirEdit() {
        let start = base()
        var mine = start
        var theirs = start
        mine.segments.remove(at: 1)
        theirs.segments[1].script = "iki — düzeltildi"
        let merged = ProjectMerge.merge(base: start, mine: mine, theirs: theirs)
        #expect(scripts(merged.project) == ["bir", "iki — düzeltildi", "üç"])
        #expect(merged.collisions.count == 1)
    }

    @Test func aClipIDeletedThatNobodyTouchedStaysDeleted() {
        let start = base()
        var mine = start
        let theirs = start
        mine.segments.remove(at: 1)
        let merged = ProjectMerge.merge(base: start, mine: mine, theirs: theirs)
        #expect(scripts(merged.project) == ["bir", "üç"])
        #expect(merged.collisions.isEmpty)
    }

    @Test func theyReorderedAndIRetypedSoBothShow() {
        let start = base()
        var mine = start
        var theirs = start
        mine.segments[0].script = "BİR"
        theirs.segments.reverse()
        let merged = ProjectMerge.merge(base: start, mine: mine, theirs: theirs).project
        #expect(scripts(merged) == ["üç", "iki", "BİR"])
    }

    @Test func whenBothReorderMineWins() {
        let start = base()
        var mine = start
        var theirs = start
        mine.segments.swapAt(0, 1)
        theirs.segments.reverse()
        let merged = ProjectMerge.merge(base: start, mine: mine, theirs: theirs).project
        #expect(scripts(merged) == ["iki", "bir", "üç"])
    }

    @Test func aClipTheyAddedLandsAfterTheOneItFollowed() {
        let start = base()
        var mine = start
        var theirs = start
        mine.segments[2].script = "üç!"
        theirs.segments.insert(segment("iki buçuk", at: 9), at: 2)
        let merged = ProjectMerge.merge(base: start, mine: mine, theirs: theirs).project
        #expect(scripts(merged) == ["bir", "iki", "iki buçuk", "üç!"])
    }

    @Test func withNothingWaitingMineSimplyReplacesTheSavedOne() {
        let start = base()
        var mine = start
        mine.title = "yeni"
        mine.segments.removeLast()
        let merged = ProjectMerge.merge(base: start, mine: mine, theirs: start)
        #expect(merged.project == mine)
        #expect(!merged.tookTheirs)
    }

    @Test func footageAClipStillUsesIsNeverDropped() {
        let start = base()
        let extra = Recording(relativePath: "media/b.mov", format: .vertical1080, camera: .back, duration: MediaTime(seconds: 10))
        var mine = start
        var theirs = start
        // They add a clip on new footage; I, meanwhile, tidy the footage list to what I use.
        let take = Take(recordingID: extra.id, sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 2)), status: .ready)
        theirs.recordings.append(extra)
        theirs.segments.append(Segment(role: .callToAction, script: "yeni", takes: [take], selectedTakeID: take.id))
        mine.recordings = start.recordings
        let merged = ProjectMerge.merge(base: start, mine: mine, theirs: theirs).project
        #expect(merged.recordings.contains { $0.id == extra.id })
        #expect(merged.segments.count == 4)
    }

    @Test func theSameThreeProjectsAlwaysMergeTheSameWay() {
        let start = base()
        var mine = start
        var theirs = start
        mine.segments[0].script = "a"
        mine.segments.swapAt(1, 2)
        theirs.segments[1].script = "b"
        theirs.segments.append(segment("dört", at: 12))
        theirs.segments.remove(at: 0)
        let first = ProjectMerge.merge(base: start, mine: mine, theirs: theirs)
        let second = ProjectMerge.merge(base: start, mine: mine, theirs: theirs)
        #expect(first.project == second.project)
        #expect(first.collisions == second.collisions)
    }
}
