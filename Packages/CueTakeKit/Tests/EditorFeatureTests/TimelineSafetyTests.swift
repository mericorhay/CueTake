import Foundation
import Testing
@testable import Domain
@testable import EditorFeature

/// Deleting a clip, transitions and many sounds: the things that must not disturb the rest.
@MainActor
struct TimelineSafetyTests {
    /// Three clips of 4 s: 0–4, 4–8, 8–12.
    private func model() -> EditorModel {
        let segments = ["1", "2", "3"].map {
            Segment(role: .mainPoint, title: $0, script: "Segment \($0)", estimatedDuration: MediaTime(seconds: 4))
        }
        return EditorModel(project: Project(title: "t", localeIdentifier: "en", segments: segments))
    }

    private func sound(_ name: String, at start: Double, length: Double, lane: Int? = nil) -> AudioClip {
        var clip = AudioClip(
            name: name,
            relativePath: "media/\(name).m4a",
            start: MediaTime(seconds: start),
            sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: length))
        )
        clip.lane = lane
        return clip
    }

    @Test func deletingAClipKeepsWhatFollowsOnItsPictures() throws {
        let model = model()
        let bed = sound("bed", at: 0, length: 12)
        let sting = sound("sting", at: 5, length: 1)
        let late = sound("late", at: 9, length: 2)
        let crossing = sound("cross", at: 7, length: 3)
        model.project.audio = [bed, sting, late, crossing]
        model.project.overlays = [
            Overlay(content: .text(OverlayText(text: "later")), start: MediaTime(seconds: 10), duration: MediaTime(seconds: 1)),
        ]
        model.project.setTransition(after: model.project.segments[1].id, kind: .crossfade)

        model.deleteSegment(at: 1)

        let audio = Dictionary(uniqueKeysWithValues: model.project.audio.map { ($0.name, $0) })
        // Over the whole video: keeps its start, loses the deleted stretch.
        #expect(audio["bed"]?.start.seconds == 0)
        #expect(abs((audio["bed"]?.timelineDuration.seconds ?? 0) - 8) < 0.001)
        // Only over the deleted clip: went with it.
        #expect(audio["sting"] == nil)
        // After it: moved back by the clip's length.
        #expect(abs((audio["late"]?.start.seconds ?? 0) - 5) < 0.001)
        // Starting inside it: begins at the cut, skipping what would have played there.
        #expect(abs((audio["cross"]?.start.seconds ?? 0) - 4) < 0.001)
        #expect(abs((audio["cross"]?.sourceRange.start.seconds ?? 0) - 1) < 0.001)
        #expect(abs((audio["cross"]?.timelineDuration.seconds ?? 0) - 2) < 0.001)
        #expect(abs((model.project.overlays.first?.start.seconds ?? 0) - 6) < 0.001)
        #expect(model.project.transitions.isEmpty)
        #expect(model.lastDeletion?.alsoRemoved == 1)

        model.undo()
        #expect(model.project.segments.count == 3)
        #expect(model.project.audio.count == 4)
        #expect(model.project.transitions.count == 1)
    }

    @Test func theLastClipCannotBeDeleted() {
        let model = model()
        model.deleteSegment(at: 0)
        model.deleteSegment(at: 0)
        #expect(!model.canDeleteSegment(at: 0))
        model.deleteSegment(at: 0)
        #expect(model.project.segments.count == 1)
    }

    @Test func transitionsFitTheirClipsAndLeaveTheLengthAlone() throws {
        let model = model()
        let duration = model.duration
        let first = model.project.segments[0].id
        let last = try #require(model.project.segments.last?.id)

        model.setTransition(after: first, kind: .slideLeft, duration: 9)
        #expect(model.project.transition(after: first)?.duration == 2)
        model.setTransition(after: last, kind: .crossfade)
        #expect(model.project.transition(after: last) == nil)
        #expect(model.duration == duration)

        model.applyTransitionEverywhere(.fadeWhite, duration: 0.6)
        #expect(model.project.transitions.count == 2)
        #expect(model.project.transitions.allSatisfy { $0.kind == .fadeWhite })

        model.removeTransition(after: first)
        #expect(model.project.transitions.count == 1)
        model.undo()
        #expect(model.project.transitions.count == 2)
    }

    @Test func transitionLooksStartOnOneClipAndEndOnTheOther() {
        for kind in ClipTransition.Kind.allCases {
            let start = TransitionLook.at(0, kind: kind)
            let end = TransitionLook.at(1, kind: kind)
            // At the start only the outgoing clip is seen in full.
            let covers = start.outgoing.opacity == 1 && start.outgoing.dx == 0 && start.outgoing.dy == 0 && start.outgoing.scale == 1
                && (start.outgoing.visible.map { $0.width == 1 && $0.height == 1 } ?? true)
            #expect(covers, "\(kind) start")
            // At the end the incoming clip is in place and nothing covers it.
            let inPlace = end.incoming.opacity == 1 && end.incoming.dx == 0 && end.incoming.dy == 0 && abs(end.incoming.scale - 1) < 0.0001
            let outgoingGone = end.outgoing.opacity == 0 || abs(end.outgoing.dx) >= 1 || (end.outgoing.visible.map { $0.width <= 0 || $0.height <= 0 } ?? false) || !end.incomingOnTop && end.outgoing.opacity == 0
            #expect(inPlace, "\(kind) end")
            #expect(outgoingGone || end.incomingOnTop, "\(kind) end cover")
        }
        #expect(ClipTransition.Kind(loose: "Dissolve") == .crossfade)
        #expect(ClipTransition.Kind(loose: "slide_up") == .slideUp)
    }

    @Test func soundsKeepTheRowTheyWereMovedTo() {
        let model = model()
        let a = sound("a", at: 0, length: 5)
        let b = sound("b", at: 1, length: 2)
        let c = sound("c", at: 6, length: 2, lane: 2)
        model.project.audio = [a, b, c]

        #expect(model.audioRows[a.id] == 0)
        #expect(model.audioRows[b.id] == 1)
        #expect(model.audioRows[c.id] == 2)
        #expect(model.audioRowCount == 3)

        // Moved up, "b" takes the row and "a", which nobody placed, makes room.
        model.moveAudio(b.id, byRows: -1)
        #expect(model.audioRows[b.id] == 0)
        #expect(model.audioRows[a.id] == 1)
        model.moveAudio(c.id, byRows: -2)
        #expect(model.audioRows[c.id] == 0)
        #expect(model.audioRowCount == 2)
    }
}
