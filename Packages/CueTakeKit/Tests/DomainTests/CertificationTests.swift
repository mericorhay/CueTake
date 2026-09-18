import Foundation
import Testing
@testable import Domain

struct CertificationTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func onlyWorkWithSomethingHappeningCounts() {
        var progress = CertificationProgress()
        progress.tick(at: start, working: true)
        // Nothing done yet: no time.
        progress.tick(at: start.addingTimeInterval(30), working: true)
        #expect(progress.activeSeconds == 0)

        progress.noteActivity(at: start.addingTimeInterval(30))
        progress.tick(at: start.addingTimeInterval(60), working: true)
        #expect(progress.activeSeconds == 30)

        // Browsing the library is not work.
        progress.tick(at: start.addingTimeInterval(90), working: false)
        #expect(progress.activeSeconds == 30)

        // Still within two minutes of the last touch: counts.
        progress.tick(at: start.addingTimeInterval(120), working: true)
        #expect(progress.activeSeconds == 60)
        // More than two minutes after it, the editor sitting open stops counting.
        progress.tick(at: start.addingTimeInterval(180), working: true)
        progress.tick(at: start.addingTimeInterval(400), working: true)
        #expect(progress.activeSeconds == 60)
    }

    @Test func aPhoneAsleepBetweenTicksBanksAMinuteAtMost() {
        var progress = CertificationProgress()
        progress.tick(at: start, working: true)
        progress.noteActivity(at: start.addingTimeInterval(3_590))
        progress.tick(at: start.addingTimeInterval(3_600), working: true)
        #expect(progress.activeSeconds == CertificationProgress.longestTick)
    }

    @Test func aProjectExportedTwiceIsOneFinishedProject() {
        var progress = CertificationProgress()
        let project = UUID()
        progress.noteFinished(project: project)
        progress.noteFinished(project: project)
        #expect(progress.finishedProjects.count == 1)
    }

    @Test func certificatesComeInOrderAndOnlyWhenEveryRequirementIsMet() {
        var progress = CertificationProgress()
        progress.activeSeconds = 99 * 3600
        for _ in 0..<15 { progress.noteFinished(project: UUID()) }
        #expect(progress.award(at: start).isEmpty)

        progress.activeSeconds = 100 * 3600
        #expect(progress.award(at: start) == [.creator])
        #expect(progress.highest == .creator)
        #expect(progress.next == .advancedCreator)

        // Hours and projects without the tasks: no Advanced.
        progress.activeSeconds = 160 * 3600
        for _ in 0..<20 { progress.noteFinished(project: UUID()) }
        #expect(progress.award(at: start).isEmpty)
        #expect(progress.standing(for: .advancedCreator).tasksLeft.count == CertificationTask.allCases.count)

        for task in CertificationTask.allCases { progress.complete(task, at: start) }
        #expect(progress.award(at: start) == [.advancedCreator])

        // The specialist needs a review that does not exist yet: never awarded on the phone.
        progress.activeSeconds = 300 * 3600
        for _ in 0..<20 { progress.noteFinished(project: UUID()) }
        for _ in 0..<10 { progress.noteWorkflowRun(at: start) }
        let specialist = progress.standing(for: .workflowSpecialist)
        #expect(specialist.readyForReview)
        #expect(!specialist.isMet)
        #expect(progress.award(at: start).isEmpty)
    }

    @Test func aPassedSignedReviewCompletesTheSpecialist() {
        var progress = CertificationProgress()
        progress.activeSeconds = 300 * 3600
        for _ in 0..<45 { progress.noteFinished(project: UUID()) }
        for task in CertificationTask.allCases { progress.complete(task, at: start) }
        for _ in 0..<10 { progress.noteWorkflowRun(at: start) }
        #expect(progress.award(at: start) == [.creator, .advancedCreator])

        progress.review = SignedReview(projectTitle: "t", score: 61, passed: false, strengths: [], improvements: ["Hook"], date: start, payload: "p", signature: "s")
        #expect(progress.award(at: start).isEmpty)
        progress.review?.score = 78
        progress.review?.passed = true
        #expect(progress.award(at: start) == [.workflowSpecialist])
    }

    @Test func aLevelIsNotSkipped() {
        var progress = CertificationProgress()
        progress.activeSeconds = 500 * 3600
        for _ in 0..<50 { progress.noteFinished(project: UUID()) }
        for task in CertificationTask.allCases { progress.complete(task, at: start) }
        // Both earned together, Creator first: Advanced is never held without it.
        #expect(progress.award(at: start) == [.creator, .advancedCreator])
    }

    @Test func tasksAreReadFromWhatTheProjectHolds() {
        let recording = Recording(relativePath: "a.mov", format: .vertical1080, camera: .front, duration: MediaTime(seconds: 10))
        let take = Take(recordingID: recording.id, sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 5)), status: .ready)
        let segment = Segment(role: .hook, script: "Merhaba", takes: [take], selectedTakeID: take.id)
        var project = Project(title: "t", localeIdentifier: "tr", segments: [segment], recordings: [recording])
        var overlay = Overlay(content: .text(OverlayText(text: "BÜYÜK")), start: .zero)
        overlay.isBehindPerson = true
        project.overlays = [overlay]
        project.effects = [TimelineEffect(start: .zero, duration: MediaTime(seconds: 2), kind: .filter(FilterSettings(look: .warm)))]

        var progress = CertificationProgress()
        progress.observe(project, at: start)
        #expect(progress.tasks[.prompterTake] != nil)
        #expect(progress.tasks[.textBehindPerson] != nil)
        #expect(progress.tasks[.colorLook] != nil)
        #expect(progress.tasks[.transition] == nil)
    }

    @Test func aCertificateKeepsItsIDAndTheProgressSurvivesAReload() throws {
        var progress = CertificationProgress()
        progress.activeSeconds = 100 * 3600
        for _ in 0..<15 { progress.noteFinished(project: UUID()) }
        progress.complete(.cleanup, at: start)
        progress.holderName = "Meriç"
        _ = progress.award(at: start)
        let id = try #require(progress.certificateID(for: .creator))
        #expect(id.hasPrefix("CT-"))
        #expect(id.count == 14)
        #expect(progress.certificateID(for: .creator) == id)
        #expect(progress.certificateID(for: .advancedCreator) == nil)

        let reloaded = try JSONDecoder().decode(CertificationProgress.self, from: JSONEncoder().encode(progress))
        #expect(reloaded == progress)
        #expect(reloaded.certificateID(for: .creator) == id)
    }
}
