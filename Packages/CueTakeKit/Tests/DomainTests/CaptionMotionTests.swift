import Foundation
import Testing
@testable import Domain

struct CaptionMotionTests {
    private func cue(_ words: [(String, Double)], from start: Double = 1, to end: Double = 3) -> PlacedCue {
        PlacedCue(
            id: UUID(),
            text: words.map(\.0).joined(separator: " "),
            range: MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: end - start)),
            words: words.map { PlacedWord(text: $0.0, range: MediaTimeRange(start: MediaTime(seconds: $0.1), duration: MediaTime(seconds: 0.3))) }
        )
    }

    @Test func everyPresetExistsAndIsNamedAfterItself() {
        #expect(CaptionStyle.presetIDs.count == 20)
        #expect(Set(CaptionStyle.presetIDs).count == 20)
        for id in CaptionStyle.presetIDs {
            #expect(CaptionStyle.preset(id).presetID == id)
        }
    }

    @Test func oldStylesDecodeAndKeepTheirArrival() throws {
        let old = #"{"presetID":"pop","relativeFontSize":0.04,"textCase":"natural","textColor":{"red":1,"green":1,"blue":1,"alpha":1},"maxWordsPerCue":3,"position":{"x":0.5,"y":0.72}}"#
        let style = try JSONDecoder().decode(CaptionStyle.self, from: Data(old.utf8))
        #expect(style.entrance == nil)
        #expect(style.resolvedEntrance == .pop)
        #expect(style.resolvedEmphasis == .none)
        #expect(style.resolvedStrokeWeight > 0)
    }

    @Test func nothingShowsOutsideTheCue() {
        let c = cue([("hello", 1), ("there", 1.5)])
        let style = CaptionStyle.preset("punch")
        #expect(CaptionAnimator.frame(for: c, wordCount: 2, style: style, at: 0.5).opacity == 0)
        #expect(CaptionAnimator.frame(for: c, wordCount: 2, style: style, at: 3.5).opacity == 0)
        #expect(CaptionAnimator.frame(for: c, wordCount: 2, style: style, at: 2).opacity == 1)
    }

    @Test func popSpringsInAndSettles() {
        let c = cue([("hello", 1)])
        let style = CaptionStyle.preset("pop")
        #expect(CaptionAnimator.frame(for: c, wordCount: 1, style: style, at: 1).scale < 0.8)
        #expect(abs(CaptionAnimator.frame(for: c, wordCount: 1, style: style, at: 2).scale - 1) < 0.001)
    }

    @Test func typewriterShowsWordsAsTheyAreSaid() {
        let c = cue([("one", 1), ("two", 1.6), ("three", 2.2)])
        let style = CaptionStyle.preset("typewriter")
        let early = CaptionAnimator.frame(for: c, wordCount: 3, style: style, at: 1.3)
        #expect(early.words[0].opacity == 1)
        #expect(early.words[1].opacity == 0)
        #expect(early.words[2].opacity == 0)
        let late = CaptionAnimator.frame(for: c, wordCount: 3, style: style, at: 2.5)
        #expect(late.words.allSatisfy { $0.opacity == 1 })
    }

    @Test func theSpokenWordStandsOut() {
        let c = cue([("one", 1), ("two", 1.6), ("three", 2.2)])
        let grow = CaptionAnimator.frame(for: c, wordCount: 3, style: .preset("punch"), at: 1.8)
        #expect(grow.words[1].isActive)
        #expect(grow.words[1].scale > 1.1)
        #expect(grow.words[0].scale == 1)

        let card = CaptionAnimator.frame(for: c, wordCount: 3, style: .preset("spotlight"), at: 1.8)
        #expect(card.words[1].box == 1)
        #expect(card.words[0].box == 0)

        let fill = CaptionAnimator.frame(for: c, wordCount: 3, style: .preset("karaoke"), at: 1.8)
        #expect(fill.words[0].isLit && fill.words[1].isLit && !fill.words[2].isLit)
    }

    @Test func typedCaptionsStillAnimateWithoutMarkingWords() {
        let typed = PlacedCue(id: UUID(), text: "no times here", range: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 3)))
        let frame = CaptionAnimator.frame(for: typed, wordCount: 3, style: .preset("bounce"), at: 0.05)
        #expect(frame.words[0].opacity > 0)
        #expect(frame.words[2].opacity == 0)
        #expect(!frame.words.contains { $0.isActive })
    }

    @Test func keywordsAndEmoji() {
        let locale = Locale(identifier: "tr-TR")
        let c = PlacedCue(id: UUID(), text: "bu para %50 *önemli*", range: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 2)))
        let shown = CaptionWords(cue: c, style: .preset("emoji"), locale: locale)
        #expect(shown.keywords == [1, 2, 3])
        #expect(shown.words[1] == "para 💰")
        #expect(shown.words[3] == "önemli")
        // Without a keyword colour nothing is marked.
        #expect(CaptionWords(cue: c, style: .preset("pop"), locale: locale).keywords.isEmpty)
        // Turkish capitals.
        #expect(CaptionWords(cue: c, style: .preset("punch"), locale: locale).words[0] == "BU")
    }

    @Test func linesBreakGreedily() {
        let lines = CaptionLineBreaker.lines(widths: [40, 40, 40, 90], space: 10, maxWidth: 100)
        #expect(lines == [[0, 1], [2], [3]])
        #expect(CaptionLineBreaker.lines(widths: [150], space: 10, maxWidth: 100) == [[0]])
    }

    @Test func tooFastCaptionsAreFound() {
        let fast = PlacedCue(id: UUID(), text: "a very long sentence shown for a blink", range: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 0.5)))
        let calm = PlacedCue(id: UUID(), text: "calm", range: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 1)))
        #expect(CaptionReadability.tooFast([fast, calm]) == [fast.id])
    }

    @Test func aPackSetsCaptionsTransitionsAndLook() {
        let recording = Recording(relativePath: "a.mov", format: .vertical1080, camera: .back, duration: MediaTime(seconds: 10))
        func segment(_ start: Double) -> Segment {
            let take = Take(recordingID: recording.id, sourceRange: MediaTimeRange(start: MediaTime(seconds: start), duration: MediaTime(seconds: 3)), status: .ready)
            return Segment(role: .hook, script: "", takes: [take], selectedTakeID: take.id)
        }
        var project = Project(title: "t", localeIdentifier: "en-US", segments: [segment(0), segment(3), segment(6)], recordings: [recording])
        project.captionStyle.position = CaptionPosition(x: 0.5, y: 0.3)

        project.apply(StylePack.named("viral")!)
        #expect(project.captionStyle.presetID == "punch")
        #expect(project.captionStyle.position.y == 0.3)
        #expect(project.transitions.count == 2)
        #expect(project.transitions.allSatisfy { $0.kind == .zoomIn })
        #expect(project.effects.count == 1)
        #expect(project.effects.first?.filter?.look == .vivid)

        // Another pack replaces the look rather than stacking a second one.
        project.apply(StylePack.named("talk")!)
        #expect(project.effects.isEmpty)
        #expect(project.transitions.allSatisfy { $0.kind == .zoomIn })
        #expect(project.captionStyle.presetID == "podcast")

        // A pack fills the cuts that have no transition; it does not overrule a chosen one.
        project.setTransition(after: project.segments[0].id, kind: .fadeBlack)
        project.transitions.removeAll { $0.after == project.segments[1].id }
        project.apply(StylePack.named("energy")!)
        let kinds = project.transitions.sorted { a, b in
            (project.segments.firstIndex { $0.id == a.after } ?? 0) < (project.segments.firstIndex { $0.id == b.after } ?? 0)
        }.map(\.kind)
        #expect(kinds == [.fadeBlack, .slideLeft])
    }

    @Test func captionsMoveOffAFollowedFace() {
        var recording = Recording(relativePath: "a.mov", format: .vertical1080, camera: .back, duration: MediaTime(seconds: 10))
        let take = Take(recordingID: recording.id, sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 5)), status: .ready)
        var project = Project(
            title: "t",
            localeIdentifier: "en-US",
            segments: [Segment(role: .hook, script: "", takes: [take], selectedTakeID: take.id)],
            recordings: [recording]
        )
        project.captionStyle.position = .center
        let c = PlacedCue(id: UUID(), text: "hi", range: MediaTimeRange(start: MediaTime(seconds: 1), duration: MediaTime(seconds: 1)))
        #expect(project.captionPosition(for: c).y == 0.5)

        recording.reframe = [VideoFocusKeyframe(time: 1, x: 0.5, y: 0.4)]
        project.recordings = [recording]
        #expect(project.captionPosition(for: c).y == 0.74)

        // A cue the user placed stays where it was put.
        var placed = c
        placed.position = .center
        #expect(project.captionPosition(for: placed).y == 0.5)
    }
}
