import Foundation
import Testing
@testable import Domain

struct SegmentRoleAnalyzerTests {
    @Test func readsStrongTurkishStructureInsteadOfAssigningByPosition() {
        let segments = [
            Segment(role: .mainPoint, script: "Bunu herkes yanlış yapıyor. Nedenini şimdi göstereyim."),
            Segment(role: .mainPoint, script: "Örneğin aynı videoyu iki farklı sırayla deneyebilirsin."),
            Segment(role: .mainPoint, script: "Takip et, yorum yaz ve kaydet."),
        ]

        let suggestions = SegmentRoleAnalyzer.suggestions(for: segments, localeIdentifier: "tr")

        #expect(suggestions.first { $0.segmentID == segments[0].id }?.role == .hook)
        #expect(suggestions.first { $0.segmentID == segments[1].id }?.role == .example)
        #expect(suggestions.first { $0.segmentID == segments[2].id }?.role == .callToAction)
    }

    @Test func leavesNeutralFirstAndLastSegmentsAlone() {
        let segments = [
            Segment(role: .mainPoint, script: "Kamerayı pencereye doğru çeviriyorum."),
            Segment(role: .mainPoint, script: "Işık yüzü daha dengeli gösteriyor."),
            Segment(role: .mainPoint, script: "Böylece görüntü daha tutarlı kalıyor."),
        ]

        #expect(SegmentRoleAnalyzer.suggestions(for: segments, localeIdentifier: "tr").isEmpty)
    }

    @Test func prefersWhatWasActuallySaidToAnOutdatedScript() {
        let recording = Recording(
            relativePath: "media/a.mov",
            format: .vertical1080,
            camera: .front,
            duration: MediaTime(seconds: 8)
        )
        let transcript = Transcript(localeIdentifier: "en", words: [
            TimedWord(text: "Follow", range: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 0.3))),
            TimedWord(text: "for", range: MediaTimeRange(start: MediaTime(seconds: 0.3), duration: MediaTime(seconds: 0.2))),
            TimedWord(text: "more", range: MediaTimeRange(start: MediaTime(seconds: 0.5), duration: MediaTime(seconds: 0.3))),
        ])
        let take = Take(
            recordingID: recording.id,
            sourceRange: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 2)),
            status: .ready,
            transcript: transcript
        )
        let segment = Segment(
            role: .mainPoint,
            script: "Here is the technical explanation from the old draft.",
            takes: [take],
            selectedTakeID: take.id
        )

        let opening = Segment(role: .mainPoint, script: "Here is the camera setup.")
        let suggestion = SegmentRoleAnalyzer.suggestions(for: [opening, segment], localeIdentifier: "en")
            .first { $0.segmentID == segment.id }
        #expect(suggestion?.role == .callToAction)
    }

    @Test func silentImportedClipsStillReceiveAnHonestBasicStructure() {
        let segments = [
            Segment(role: .custom("1"), title: "IMG_1001", script: "", estimatedDuration: MediaTime(seconds: 3)),
            Segment(role: .custom("2"), title: "IMG_1002", script: "", estimatedDuration: MediaTime(seconds: 8)),
            Segment(role: .custom("3"), title: "IMG_1003", script: "", estimatedDuration: MediaTime(seconds: 4)),
        ]

        let suggestions = SegmentRoleAnalyzer.suggestions(for: segments, localeIdentifier: "tr")

        #expect(suggestions.first { $0.segmentID == segments[0].id }?.role == .hook)
        #expect(suggestions.first { $0.segmentID == segments[1].id }?.role == .mainPoint)
        #expect(suggestions.first { $0.segmentID == segments[2].id }?.role == .mainPoint)
        #expect(!suggestions.contains { $0.role == .callToAction })
    }

    @Test func handWrittenCaptionsProvideMeaningWithoutAnAudioTrack() {
        let opening = Segment(role: .mainPoint, script: "", estimatedDuration: MediaTime(seconds: 3))
        let closing = Segment(
            role: .mainPoint,
            script: "",
            estimatedDuration: MediaTime(seconds: 2),
            captions: [CaptionCue(
                text: "Devamı için takip et ve kaydet",
                range: MediaTimeRange(start: .zero, duration: MediaTime(seconds: 2))
            )]
        )

        let suggestions = SegmentRoleAnalyzer.suggestions(for: [opening, closing], localeIdentifier: "tr")

        #expect(suggestions.first { $0.segmentID == closing.id }?.role == .callToAction)
    }

    @Test func automaticApplicationReplacesNumberedImportsBeforeTheEditorAppears() {
        var segments = [
            Segment(role: .custom("1"), title: "IMG_1001", script: "Bugün yürüyüşe çıktım.", estimatedDuration: MediaTime(seconds: 3)),
            Segment(role: .custom("2"), title: "IMG_1002", script: "Hava çok güzeldi.", estimatedDuration: MediaTime(seconds: 5)),
        ]

        let changed = SegmentRoleAnalyzer.applyAutomatically(to: &segments, localeIdentifier: "tr")

        #expect(changed == 2)
        #expect(segments.map(\.role) == [.hook, .mainPoint])
        #expect(segments.allSatisfy { $0.metadata["roleAssignment"] == "automatic" })
    }

    @Test func automaticApplicationNeverOverwritesManualOrAIRoles() {
        var manual = Segment(role: .custom("1"), title: "IMG_1001", script: "")
        manual.metadata["roleAssignment"] = "manual"
        var ai = Segment(role: .custom("2"), title: "IMG_1002", script: "")
        ai.metadata["roleAssignment"] = "ai"
        var segments = [manual, ai]

        let changed = SegmentRoleAnalyzer.applyAutomatically(to: &segments, localeIdentifier: "tr")

        #expect(changed == 0)
        #expect(segments.map(\.role) == [.custom("1"), .custom("2")])
    }

    @Test func automaticSuggestionsChooseOneStrongestRolePerClip() {
        let clip = Segment(
            role: .custom("1"),
            title: "",
            script: "Dur! Neden yanlış yaptığını görmek için takip et ve yorum yaz.",
            estimatedDuration: MediaTime(seconds: 5)
        )

        let suggestions = SegmentRoleAnalyzer.automaticSuggestions(for: [clip], localeIdentifier: "tr")

        #expect(suggestions.count == 1)
        #expect(suggestions[0].segmentID == clip.id)
    }
}
