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
}
