import Foundation
import Testing
@testable import Domain

/// Tools over stretches of the video, and the two listeners side by side.
struct EffectsAndSpeechTests {
    private func project(lengths: [Double]) -> Project {
        Project(
            title: "t",
            localeIdentifier: "tr-TR",
            segments: lengths.map { Segment(role: .mainPoint, script: "", estimatedDuration: MediaTime(seconds: $0)) }
        )
    }

    private func blur(from: Double, to: Double, strength: Double = 0.5) -> TimelineEffect {
        TimelineEffect(
            start: MediaTime(seconds: from),
            duration: MediaTime(seconds: to - from),
            kind: .background(BackgroundSettings(style: .blur, strength: strength))
        )
    }

    @Test func aBackgroundCoversOnlyItsStretch() {
        var project = project(lengths: [10, 10])
        project.effects = [blur(from: 4, to: 13)]

        let first = project.stretches(ofSegmentAt: 0)
        #expect(first.count == 2)
        #expect(first[0].background == nil && abs(first[0].to - 4) < 0.001)
        #expect(first[1].background?.style == .blur && abs(first[1].to - 10) < 0.001)

        let second = project.stretches(ofSegmentAt: 1)
        #expect(second.count == 2)
        #expect(second[0].background != nil && abs(second[0].to - 3) < 0.001)
        #expect(second[1].background == nil)
    }

    @Test func theTopEffectWinsWhereTheyOverlap() {
        var project = project(lengths: [10])
        project.effects = [blur(from: 0, to: 10, strength: 0.2), blur(from: 5, to: 10, strength: 0.9)]
        let stretches = project.stretches(ofSegmentAt: 0)
        #expect(stretches.count == 2)
        #expect(stretches[1].background?.strength == 0.9)
        #expect(project.backgrounds(ofSegmentAt: 0).count == 2)
    }

    @Test func sliversAreMergedAway() {
        var project = project(lengths: [10])
        project.effects = [blur(from: 0.02, to: 9.99)]
        #expect(project.stretches(ofSegmentAt: 0).count == 1)
    }

    @Test func oldClipBackgroundsBecomeEffects() throws {
        var old = project(lengths: [3, 5])
        old.segments[1].background = .studio
        let data = try JSONEncoder().encode(old)
        let opened = try JSONDecoder().decode(Project.self, from: data)
        #expect(opened.segments[1].background == nil)
        #expect(opened.effects.count == 1)
        #expect(opened.effects[0].background?.style == .studio)
        #expect(abs(opened.effects[0].start.seconds - 3) < 0.001)
        #expect(abs(opened.effects[0].duration.seconds - 5) < 0.001)
    }

    @Test func settingsThatLookDifferentRenderDifferentFiles() {
        let soft = BackgroundSettings(style: .blur, strength: 0.2)
        let strong = BackgroundSettings(style: .blur, strength: 0.8)
        let black = BackgroundSettings(style: .black, strength: 0.2)
        #expect(soft.token != strong.token)
        // Strength means nothing for a flat colour, so it does not force a new render.
        #expect(black.token == BackgroundSettings(style: .black, strength: 0.9).token)
    }

    // MARK: - Two listeners

    private func words(_ items: [(String, Double, Double)]) -> [TimedWord] {
        items.map { TimedWord(text: $0.0, range: MediaTimeRange(start: MediaTime(seconds: $0.1), duration: MediaTime(seconds: $0.2 - $0.1))) }
    }

    @Test func passagesBreakAtSharedSilence() {
        let device = words([("merhaba", 0.2, 0.6), ("dünya", 0.7, 1.1), ("bugün", 3.0, 3.4)])
        let cloud = words([("Merhaba", 0.25, 0.6), ("dünya.", 0.7, 1.05), ("bugün", 3.05, 3.4), ("güzel", 3.5, 3.9)])
        let versions = TranscriptVersions(localeIdentifier: "tr-TR", device: device, cloud: cloud)
        #expect(versions.passages.count == 2)
        // The same words either way: the phone's timings are kept.
        #expect(versions.passages[0].choice == .device)
        // The phone missed a word: the server's version.
        #expect(versions.passages[1].choice == .cloud)
        #expect(versions.merged.words.map(\.text) == ["merhaba", "dünya", "bugün", "güzel"])
        #expect(versions.disputed.count == 1)
    }

    @Test func theScriptSettlesADisagreement() {
        let device = words([("kedi", 0.0, 0.4), ("uçtu", 0.5, 0.9)])
        let cloud = words([("kediler", 0.0, 0.4), ("koştu", 0.5, 0.9)])
        let versions = TranscriptVersions(localeIdentifier: "tr-TR", device: device, cloud: cloud, script: "Kediler koştu")
        #expect(versions.passages.first?.choice == .cloud)
    }

    @Test func theUsersChoiceIsNotOverruledByALateAnswer() {
        var project = project(lengths: [4])
        let recording = Recording(relativePath: "media/a.mov", format: .vertical1080, camera: .front, duration: MediaTime(seconds: 4))
        var versions = TranscriptVersions(
            localeIdentifier: "tr-TR",
            device: words([("bir", 1.0, 1.3)]),
            cloud: words([("biri", 1.0, 1.3)])
        )
        let passage = versions.passages[0].id
        versions.choose(.device, forPassage: passage, by: .rule)
        project.recordings = [recording]
        project.recordings[0].speech = versions
        let take = Take(recordingID: recording.id, sourceRange: MediaTimeRange(start: MediaTime(seconds: 0.5), duration: MediaTime(seconds: 3)), status: .ready)
        project.segments[0].takes = [take]
        project.segments[0].selectedTakeID = take.id

        project.choose(.cloud, forPassage: passage, inRecording: recording.id, by: .user)
        #expect(project.segments[0].selectedTake?.transcript?.words.first?.text == "biri")
        // Take-relative: the take starts half a second into the file.
        #expect(abs((project.segments[0].selectedTake?.transcript?.words.first?.range.start.seconds ?? 0) - 0.5) < 0.001)
        #expect(project.segments[0].captions.first?.text == "biri")

        project.choose(.device, forPassage: passage, inRecording: recording.id, by: .ai)
        #expect(project.segments[0].selectedTake?.transcript?.words.first?.text == "biri")
    }
}
